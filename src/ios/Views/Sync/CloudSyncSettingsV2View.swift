import SwiftUI

/// V2 iCloud Sync settings page. Replaces the v1 CloudSyncSettingsView
/// when v2 is enabled. Drives:
/// - Master enable/disable
/// - This device's friendly name
/// - Per-category upload toggles (Chat / SessionFiles / Skills / Providers / Env)
/// - Per-file size cap
/// - Discovered remote devices (read from sync_devices table populated
///   by mergeDevice hydrator on inbound SyncDeviceV2 records)
struct CloudSyncSettingsV2View: View {
    @State private var v2Enabled: Bool = false
    @State private var deviceName: String = ""
    @State private var deviceNameDraft: String = ""
    @State private var showDeviceNameEditor: Bool = false
    @State private var categoriesEnabled: [UploadPolicy.Category: Bool] = [:]
    @State private var maxFileSizeMB: Int = 1
    @State private var remoteDevices: [SyncDevice] = []
    @State private var statusText: String = ""
    // [T-ios-migration-timer-sessionlist-uaf-crash] 5s refresh cadence is driven by
    // a `.task` async loop (see refreshLoop), NOT a process-lived
    // `Timer.publish(every:5).autoconnect()` + `.onReceive`. A graph-bound Combine
    // publisher's sink is a SwiftUI attribute AttributeGraph re-creates on every body
    // transaction; a tick delivered while it is torn down/rebuilt releases the dangling
    // `SubscriptionView` sink closure → use-after-free (CODESIGNING Invalid Page,
    // TestFlight crash1/crash2, 1.10(43)). Same mechanism 665c15fb fixed in ContentView;
    // that commit converted only the ContentView binding point, leaving this view and
    // SyncMigrationDetailView on the crashing pattern.
    private static let refreshIntervalSeconds: UInt64 = 5

    var body: some View {
        CodySettingsScrollPage {
            syncSection
            if v2Enabled {
                deviceSection
                uploadSection
                remoteDevicesSection
            }
        }
        .navigationTitle("iCloud Sync")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        // [T-ios-migration-timer-sessionlist-uaf-crash] `.task` async refresh loop
        // replaces the old `.task { await refresh() }` + `.onReceive(timer)` pair, so
        // there is no graph-bound Combine sink to be released mid-transaction (the crash
        // that pattern caused — see refreshIntervalSeconds). SwiftUI cancels this Task
        // on teardown.
        .task { await refreshLoop() }
        .sheet(isPresented: $showDeviceNameEditor) {
            deviceNameEditor
        }
    }

    private var deviceNameEditor: some View {
        NavigationStack {
            CodySettingsScrollPage {
                VStack(alignment: .leading, spacing: CodySpacing.xs) {
                    TextField("Device name", text: $deviceNameDraft)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(saveDeviceName)
                        .settingsNovaField("Device Name")
                    Text("Friendly name shown to your other Cody devices.")
                        .settingsNovaFooter()
                }

                SettingsNovaEditorActions(save: saveDeviceName) {
                    showDeviceNameEditor = false
                }
            }
            .navigationTitle("Device Name")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }

    private func saveDeviceName() {
        let trimmed = deviceNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        UploadPolicy.customDeviceName = trimmed.isEmpty ? nil : trimmed
        deviceName = UploadPolicy.customDeviceName ?? DeviceIdentity.deviceName
        showDeviceNameEditor = false
        Task { await markDeviceDirty() }
    }

    private var syncSection: some View {
        let enabled = Binding(
            get: { v2Enabled },
            set: { newValue in
                if #available(iOS 17.0, *) { SyncV2Bootstrap.setEnabled(newValue) }
                v2Enabled = newValue
            }
        )
        return CodySettingsNovaSection(footer: "Toggle takes effect on next app launch.") {
            CodySettingsNovaToggleRow("Enable iCloud Sync", systemImage: nil, isOn: enabled)
                .tint(.green)
                .accessibilityRepresentation {
                    Toggle("Enable iCloud Sync", isOn: enabled)
                }
            if !statusText.isEmpty {
                CodySettingsNovaDivider(leadingInset: 18)
                CodySettingsNovaNavRow("Status", systemImage: nil) {
                    Text(verbatim: AppLocalized(String.LocalizationValue(statusText)))
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                } destination: {
                    SyncMigrationDetailView()
                }
            }
        }
    }

    private var deviceSection: some View {
        CodySettingsNovaSection(
            "Upload (This Device)",
            footer: "This device name is broadcast to your other devices in the iCloud Sync zone."
        ) {
            CodySettingsNovaActionRow("Name", systemImage: nil, showsDisclosure: true, action: {
                deviceNameDraft = deviceName
                showDeviceNameEditor = true
            }) {
                Text(deviceName)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
            }
        }
    }

    private var uploadSection: some View {
        CodySettingsNovaSection(
            footer: "Choose which data this device pushes to iCloud. API keys and secrets are synced securely via iCloud Keychain."
        ) {
            ForEach(UploadPolicy.Category.allCases, id: \.self) { category in
                if category != UploadPolicy.Category.allCases.first {
                    CodySettingsNovaDivider(leadingInset: 18)
                }
                uploadToggle(category)
            }
            if categoriesEnabled[.sessionFiles] ?? true {
                CodySettingsNovaDivider(leadingInset: 18)
                Menu {
                    Picker("Max Per-File Size", selection: $maxFileSizeMB) {
                        Text("256 KB").tag(0)
                        Text("1 MB").tag(1)
                        Text("4 MB").tag(4)
                        Text("16 MB").tag(16)
                        Text("64 MB").tag(64)
                    }
                } label: {
                    SettingsNovaPickerLabel(
                        title: "Max Per-File Size",
                        value: maxFileSizeMB == 0 ? Text("256 KB") : Text("\(maxFileSizeMB) MB")
                    )
                }
                .buttonStyle(CodyPressableButtonStyle())
                .onChange(of: maxFileSizeMB) { newValue in
                    UploadPolicy.maxFileSizeBytes = newValue == 0 ? 256 * 1024 : newValue * 1024 * 1024
                }
            }
        }
    }

    private func uploadToggle(_ category: UploadPolicy.Category) -> some View {
        let title = LocalizedStringKey(category.displayName)
        let enabled = Binding(
            get: { categoriesEnabled[category] ?? true },
            set: { newValue in
                UploadPolicy.setEnabled(category, newValue)
                categoriesEnabled[category] = newValue
                Task { await markDeviceDirty() }
            }
        )
        return CodySettingsNovaToggleRow(title, systemImage: nil, isOn: enabled)
            .tint(.green)
            .accessibilityRepresentation {
                Toggle(title, isOn: enabled)
            }
    }

    private var remoteDevicesSection: some View {
        CodySettingsNovaSection(
            "Other Devices",
            footer: "Devices that are signed in to the same iCloud account and have sync enabled. Last seen reflects the most recent push from that device."
        ) {
            if remoteDevices.isEmpty {
                Text("No other devices found yet. Devices appear here once they enable iCloud Sync.")
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .settingsNovaControlRow()
            } else {
                ForEach(remoteDevices, id: \.id) { device in
                    if device.id != remoteDevices.first?.id {
                        CodySettingsNovaDivider(leadingInset: 18)
                    }
                    remoteDeviceRow(device)
                }
            }
        }
    }

    private func remoteDeviceRow(_ device: SyncDevice) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(device.deviceName)
                    Spacer()
                    lastSeen(device)
                }
                VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                    Text(device.deviceName)
                    lastSeen(device)
                }
            }
            .font(CodyTypography.bodyLarge)
            .foregroundStyle(CodyColors.textPrimary)

            if !device.uploadTypes.isEmpty {
                Text(uploadTypesSummary(device.uploadTypes))
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
            }
        }
        .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
    }

    private func lastSeen(_ device: SyncDevice) -> some View {
        Text(relativeDate(device.lastSeen))
            .font(CodyTypography.labelSmall)
            .monospacedDigit()
            .foregroundStyle(CodyColors.textTertiary)
    }

    /// [T-ios-migration-timer-sessionlist-uaf-crash] Self-cancelling 5s refresh loop
    /// driven by `.task`, replacing the graph-bound `Timer.publish().autoconnect()` +
    /// `.onReceive` that AttributeGraph could tear down mid-transaction (UAF). SwiftUI
    /// cancels this Task on teardown, so no dangling subscription survives. Refreshes
    /// once immediately (mirroring the old `.task { await refresh() }`) then every 5s;
    /// skips the refresh while backgrounded and resumes on the next foreground tick.
    @MainActor
    private func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: Self.refreshIntervalSeconds * 1_000_000_000)
            } catch {
                return  // cancelled during sleep
            }
            let backgrounded: Bool
            if #available(iOS 17.0, *) {
                backgrounded = SyncCore.shared.isAppInBackground
            } else {
                backgrounded = false
            }
            if !backgrounded {
                await refresh()
            }
        }
    }

    @MainActor
    private func refresh() async {
        if #available(iOS 17.0, *) {
            v2Enabled = SyncV2Bootstrap.isEnabled
        }
        deviceName = UploadPolicy.customDeviceName ?? DeviceIdentity.deviceName
        for cat in UploadPolicy.Category.allCases {
            categoriesEnabled[cat] = UploadPolicy.isEnabled(cat)
        }
        let bytes = UploadPolicy.maxFileSizeBytes
        maxFileSizeMB = bytes < 1024 * 1024 ? 0 : Int((Double(bytes) / (1024 * 1024)).rounded())
        let me = DeviceIdentity.deviceId
        let all = await ChatStore.shared.listSyncDevices()
        remoteDevices = all.filter { $0.id != me }.sorted { $0.lastSeen > $1.lastSeen }
        if #available(iOS 17.0, *), v2Enabled {
            statusText = SyncCore.shared.isRunning ? "Running" : "Starting"
        } else {
            statusText = "Off"
        }
    }

    /// Whenever the user changes their upload preferences or device
    /// name, re-broadcast our SyncDeviceV2 record so peers learn about
    /// the new state.
    private func markDeviceDirty() async {
        await ChatStore.shared.markDirty(
            recordType: "SyncDeviceV2",
            recordId: DeviceIdentity.deviceId
        )
        if #available(iOS 17.0, *) {
            SyncCore.shared.scheduleSend(delay: 1)
        }
    }

    private func uploadTypesSummary(_ csv: [String]) -> String {
        guard !csv.isEmpty else { return AppLocalized("No categories enabled") }
        return csv.joined(separator: " · ")
    }

    private func relativeDate(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return AppLocalized("Just now") }
        let mins = secs / 60
        if mins < 60 { return AppLocalized("\(mins) min ago") }
        let hrs = mins / 60
        if hrs < 24 { return AppLocalized("\(hrs) hr ago") }
        let days = hrs / 24
        return AppLocalized("\(days) day ago")
    }
}
