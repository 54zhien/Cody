//
//  ContentView+RemoteSessions.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  ContentView, remote device sessions: sessions synced from other devices,
//  shown in their own sections with RemoteSessionRow. Its logger is stored in
//  ContentView.swift.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

extension ContentView {
    // MARK: - Remote Device Sessions

    /// [T-ios-session-list-equatable-jank] id→remote ChatSession lookup, keyed
    /// "deviceId:sessionId". Lets the remote-session rows resolve their model by
    /// id so the ForEach below diffs `[String]`, not `[ChatSession]`.
    private var remoteSessionsById: [String: ChatSession] {
        var d: [String: ChatSession] = [:]
        for entry in remoteDeviceSessions {
            for s in entry.sessions { d["\(entry.device.id):\(s.id)"] = s }
        }
        return d
    }

    @ViewBuilder
    var remoteDeviceSessionSections: some View {
        let _ = syncLog.info("[iCloud] remoteDeviceSessionSections evaluated: \(remoteDeviceSessions.count) devices, total sessions=\(remoteDeviceSessions.reduce(0) { $0 + $1.sessions.count })")
        let byId = remoteSessionsById
        // [T-ios-session-list-equatable-jank] Project to (deviceId, deviceName,
        // sessionIds) so SwiftUI diffs id strings instead of deep-comparing the
        // [ChatSession] value array on every transaction flush — same fix as the
        // local sidebar list. (This remote section was the path still triggering
        // Array<ChatSession>.== in the HangDetector stacks after the local-list
        // fix landed.)
        let deviceSections: [(deviceId: String, name: String, ids: [String])] =
            remoteDeviceSessions.compactMap { entry in
                let ids = entry.sessions.filter(matchesRemoteSearch).map(\.id)
                guard !ids.isEmpty else { return nil }
                return (deviceId: entry.device.id, name: entry.device.deviceName, ids: ids)
            }
        ForEach(deviceSections, id: \.deviceId) { entry in
            let _ = syncLog.info("[iCloud] rendering section for device=\(entry.deviceId) name=\(entry.name) sessions=\(entry.ids.count)")
            Section {
                ForEach(entry.ids, id: \.self) { sessionId in
                    if let session = byId["\(entry.deviceId):\(sessionId)"] {
                        let route = "remote:\(entry.deviceId):\(session.id)"
                        Button {
                            switchToSession(route)
                        } label: {
                            RemoteSessionRow(session: session, isFrameless: !isWideLayout)
                        }
                        .buttonStyle(SessionRowPressStyle())
                        .accessibilityAddTraits(isSessionHighlighted(route) ? .isSelected : [])
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: CodyRadius.control)
                                .fill(novaDestination == .home && isSessionHighlighted(route)
                                      ? CodyColors.interactiveSecondaryBg : .clear)
                                .padding(.horizontal, isWideLayout ? CodySpacing.xsPlus : 0)
                        )
                        .contentShape(.contextMenuPreview, SessionMenuLiftShape())
                        .contextMenu {
                            Button {
                                // [T-ios-state-publish-offmain-crash] @MainActor
                                // so the @State write stays on the main thread.
                                let sid = session.id
                                let deviceId = entry.deviceId
                                Task { @MainActor in
                                    if let forked = await SessionForkManager.shared.forkSession(
                                        remoteSessionId: sid, remoteDeviceId: deviceId
                                    ) {
                                        refreshSessionList()
                                        switchToSession(forked.id)
                                    }
                                }
                            } label: {
                                Label("Fork Session", systemImage: "arrow.branch")
                            }
                        } preview: {
                            SessionMenuPreview(title: session.title, sessionID: nil)
                        }
                    }
                }
            } header: {
                Label(entry.name, systemImage: "iphone")
                    .modifier(SidebarSectionHeaderStyle())
            }
        }
    }

    var hasMatchingRemoteSessions: Bool {
        remoteDeviceSessions.contains { $0.sessions.contains(where: matchesRemoteSearch) }
    }

    private func matchesRemoteSearch(_ session: ChatSession) -> Bool {
        guard isSearching, !searchQuery.isEmpty else { return true }
        let terms = SearchKeywords.terms(searchQuery)
        return SearchKeywords.firstHit(in: session.title ?? "", terms: terms) != nil
            || SearchKeywords.firstHit(in: session.lastMessage ?? "", terms: terms) != nil
    }

    // [T-ios-state-publish-offmain-crash] @MainActor: writes `remoteDeviceSessions`
    // (@State) after several ChatStore (actor) awaits; without this the
    // continuation could resume off-main and publish state from a background
    // thread (the [ChatSession] AttributeGraph-compare crash path).
    @MainActor
    func refreshRemoteDeviceSessions() async {
        let allDevices = await ChatStore.shared.listSyncDevices()
        let devices = allDevices.filter { $0.id != DeviceIdentity.deviceId }
        syncLog.info("[RemoteSync] refreshRemoteDeviceSessions: \(allDevices.count) total devices, \(devices.count) remote (self=\(DeviceIdentity.deviceId))")
        var result: [(device: SyncDevice, sessions: [ChatSession])] = []
        for device in devices {
            let remoteSessions = await ChatStore.shared.listRemoteSessions(deviceId: device.id)
            syncLog.info("[RemoteSync] device \(device.id) (\(device.deviceName)): \(remoteSessions.count) sessions")
            if !remoteSessions.isEmpty {
                result.append((device: device, sessions: remoteSessions))
            }
        }
        syncLog.info("[RemoteSync] Final result: \(result.count) devices with sessions")
        remoteDeviceSessions = result
    }

}
