import SwiftUI

private let shareLog = AppLogger(category: "Share")
private let draftLog = AppLogger(category: "DraftSession")

extension ContentView {
    // Apply app font scaling inside each column's hosting boundary.
    var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sessionList(useNavigationLinks: false)
                .appFontScale()
        } detail: {
            Group {
                switch novaTab {
                case .chat: detailView
                case .explore: novaExplore
                case .files: novaFiles
                }
            }
            .appFontScale()
        }
    }

    var showNovaTabBar: Bool {
        !novaKeyboard.isVisible && !isNovaDrawerOpen && !isSelecting && navigationPath.isEmpty
    }

    var stackLayout: some View {
        CodySidebarDrawer(isOpen: $isNovaDrawerOpen, edgeDragEnabled: !isSelecting && navigationPath.isEmpty) {
            novaTabContent
                .accessibilityHidden(isNovaDrawerOpen)
                .overlay(alignment: .bottom) {
                    if showNovaTabBar {
                        CodyNovaTabBar(selection: $novaTab, onReselect: { tab in
                            if tab == .chat { openNovaDrawer() }
                        })
                        .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: showNovaTabBar)
        } drawer: {
            novaDrawer
        }
    }

    @ViewBuilder
    private var novaTabContent: some View {
        switch novaTab {
        case .chat:
            NavigationStack(path: $navigationPath) {
                novaHostedChat(novaActiveSessionId)
                    .id(novaActiveSessionId)
                    .navigationDestination(for: String.self) { id in
                        novaHostedChat(id, isPushed: true)
                            .id(id)
                    }
            }
        case .explore:
            NavigationStack { novaExplore }
        case .files:
            NavigationStack { novaFiles }
        }
    }

    private func novaHostedChat(_ id: String, isPushed: Bool = false) -> some View {
        sessionChat(id)
            .environment(\.isNovaHostedChat, !isPushed)
            .environment(\.openNovaDrawer, isPushed ? nil : { openNovaDrawer() })
            .environment(\.novaNewChatAction, { startNewNovaChat() })
            .environment(\.novaTabBarBottomInset, showNovaTabBar ? CodyNovaTabBar.totalClearance : 0)
            .onAppear {
                novaChatAppeared(id, isPushed: isPushed)
                shareLog.info("🔄SESSION stackNav APPEAR id=\(id)")
                HangDetector.mark("chat appear")
            }
            .onDisappear {
                shareLog.info("🔄SESSION stackNav DISAPPEAR id=\(id)")
                HangDetector.mark("chat disappear")
            }
    }

    private var novaExplore: some View {
        NovaExploreView(
            bottomClearance: isWideLayout ? 0 : CodyNovaTabBar.totalClearance,
            onOpenBrowser: { activeToolSheet = .browser },
            onOpenTerminal: { showTerminal = true },
            onOpenSettings: { activeToolSheet = .settings }
        )
        .modifier(NovaDestinationToolbar(onOpenDrawer: isWideLayout ? nil : openNovaDrawer))
    }

    private var novaFiles: some View {
        NovaFilesTabView(bottomClearance: !isWideLayout && showNovaTabBar ? CodyNovaTabBar.totalClearance : 0)
            .modifier(NovaDestinationToolbar(onOpenDrawer: isWideLayout ? nil : openNovaDrawer))
    }

    @ViewBuilder
    private var detailView: some View {
        if let id = selectedSessionId {
            sessionChat(id)
                .id(id)
                .onAppear {
                    let localId = Self.remoteSessionRoute(id) == nil ? persistedSessionId(for: id) : nil
                    AIChatViewModel.activeSessionId = localId
                    if let localId { SessionBadgeStore.shared.remove(.unread, for: localId) }
                    AlwaysOnController.shared.chatSelectionChanged(to: id)
                    draftLog.info("🔑DRAFT detailView APPEAR id=\(id) effectiveId=\(localId ?? "nil") isDraft=\(Self.isNewSessionId(id))")
                }
                .onDisappear {
                    draftLog.info("🔑DRAFT detailView DISAPPEAR id=\(id)")
                }
        } else {
            VStack(spacing: CodySpacing.md) {
                CodyListIconBadge(systemImage: "bubble.left.and.bubble.right", tint: .neutral)
                Text("No Conversation Selected")
                    .font(CodyTypography.titleLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                Text("Select a conversation or start a new one")
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(CodySpacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CodyColors.bgCanvas)
        }
    }

    @ViewBuilder
    private func sessionChat(_ id: String) -> some View {
        if let remote = Self.remoteSessionRoute(id) {
            AIChatView(sessionId: remote.sessionId, remoteDeviceId: remote.deviceId)
        } else {
            // The host's .id remains the draft route after persistence, so
            // the existing StateObject stays mounted. Pass the real ID so a
            // later appearance can recover the same VM from the cache.
            AIChatView(sessionId: persistedSessionId(for: id),
                       draftId: Self.isNewSessionId(id) ? id : nil,
                       initialGroupId: Self.extractGroupId(from: id))
        }
    }
}

private struct NovaDestinationToolbar: ViewModifier {
    let onOpenDrawer: (() -> Void)?

    func body(content: Content) -> some View {
        content.toolbar {
            if let onOpenDrawer {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onOpenDrawer) {
                        Label("Open sidebar", systemImage: "line.3.horizontal")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}
