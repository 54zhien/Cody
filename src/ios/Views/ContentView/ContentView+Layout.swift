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
                switch novaDestination {
                case .home: detailView
                case .more: novaExplore(isWide: true)
                case .tool(let tool): novaTool(tool, isWide: true)
                }
            }
            .appFontScale()
        }
    }

    var showNovaTabBar: Bool {
        !novaKeyboard.isVisible && !isSelecting && navigationPath.isEmpty
    }

    private var novaBottomClearance: CGFloat {
        showNovaTabBar ? CodyNovaTabBar.totalClearance : 0
    }

    private var novaSidebarHasUnread: Bool {
        let activeId = persistedSessionId(for: novaActiveSessionId)
        return sidebarBadgeStore.unreadSessionIds.contains { $0 != activeId }
    }

    var stackLayout: some View {
        CodySidebarDrawer(isOpen: $isNovaDrawerOpen, edgeDragEnabled: !isSelecting && navigationPath.isEmpty) {
            novaDestinationContent
                .environment(\.novaSidebarHasUnread, novaSidebarHasUnread)
                .accessibilityHidden(isNovaDrawerOpen)
                .overlay(alignment: .bottom) {
                    if showNovaTabBar {
                        CodyNovaTabBar(
                            selection: $novaDestination,
                            tabStore: novaTabStore,
                            pinDragState: novaPinDragState,
                            onSelectDestination: selectNovaDestination,
                            onReselect: { destination in
                                if destination == .home { openNovaDrawer() }
                            }
                        )
                        .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay {
                    if let draggingTool = novaPinDragState.draggingTool {
                        GeometryReader { geo in
                            let origin = geo.frame(in: .global).origin
                            let localPoint = CGPoint(
                                x: novaPinDragState.dragLocation.x - origin.x,
                                y: novaPinDragState.dragLocation.y - origin.y
                            )
                            let hovering = novaPinDragState.isHoveringTabBar
                            NovaExploreCardBody(tool: draggingTool, isPinned: novaTabStore.isPinned(draggingTool))
                                .frame(width: hovering ? 120 : 164)
                                .scaleEffect(hovering ? 0.45 : 1.03)
                                .opacity(hovering ? 0.0 : 1.0)
                                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                                .position(localPoint)
                                .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: hovering)
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
                }
                .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: showNovaTabBar)
        } drawer: {
            novaDrawer
        }
    }

    @ViewBuilder
    private var novaDestinationContent: some View {
        switch novaDestination {
        case .home:
            NavigationStack(path: $navigationPath) {
                novaHostedChat(novaActiveSessionId)
                    .id(novaActiveSessionId)
                    .navigationDestination(for: String.self) { id in
                        novaHostedChat(id, isPushed: true)
                            .id(id)
                    }
            }
        case .more:
            NavigationStack {
                novaExplore(isWide: false)
                    .toolbar(.hidden, for: .navigationBar)
            }
        case .tool(let tool):
            NavigationStack { novaTool(tool, isWide: false) }
                .id(tool)
        }
    }

    private func novaHostedChat(_ id: String, isPushed: Bool = false) -> some View {
        sessionChat(id)
            .environment(\.isNovaHostedChat, !isPushed)
            .environment(\.openNovaDrawer, isPushed ? nil : { openNovaDrawer() })
            .environment(\.novaNewChatAction, { startNewNovaChat() })
            .environment(\.novaTabBarBottomInset, !isPushed && showNovaTabBar
                         ? novaBottomClearance : 0)
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

    private func novaExplore(isWide: Bool) -> some View {
        NovaExploreView(
            tabStore: novaTabStore,
            pinDragState: novaPinDragState,
            bottomClearance: isWide ? 0 : novaBottomClearance,
            onOpenDrawer: isWide ? { columnVisibility = .all } : openNovaDrawer,
            onSelectTool: { selectNovaDestination(.tool($0)) },
            onOpenSettings: { activeToolSheet = .settings }
        )
    }

    private func novaTool(_ tool: CodyNovaPinnedTool, isWide: Bool) -> some View {
        let clearance = isWide ? 0 : novaBottomClearance
        return Group {
            if tool == .files {
                NovaFilesTabView(bottomClearance: clearance)
            } else {
                novaToolContent(tool)
                    .modifier(NovaBottomScrollEdgeHost(clearance: clearance))
            }
        }
        .modifier(NovaDestinationToolbar(onOpenDrawer: isWide ? nil : openNovaDrawer))
    }

    @ViewBuilder
    private func novaToolContent(_ tool: CodyNovaPinnedTool) -> some View {
        switch tool {
        case .skills: SkillsManagementView()
        case .mcp: MCPIntegrationsView()
        case .agentTools: ToolsSettingsView()
        case .subAgents: HelperSettingsView()
        case .soul: SoulSettingsView()
        case .memory: MemoryManagementView()
        case .providers: ProviderInstancesView()
        case .usage: UsageStatsView()
        case .alarms:
            Text("Alarms are unavailable on this device.")
                .font(CodyTypography.bodyMedium)
                .foregroundStyle(CodyColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(CodySpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CodyColors.bgCanvas)
                .navigationTitle(tool.title)
        case .files, .terminal, .browser:
            EmptyView()
        }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenDrawer) {
                        CodyDrawerGlyph(size: 23)
                    }
                    .accessibilityLabel("Open sidebar")
                }
            }
        }
    }
}

/// Shared native iOS 26 `.soft` bottom scroll-edge fade matching `NovaExploreView` across every
/// Nova tab page (Files, Skills, MCP, Tools, Memory, Soul, Providers, Usage, etc.).
struct NovaBottomScrollEdgeHost: ViewModifier {
    let clearance: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive {
            content
                .modifier(CodyTopScrollEdgeHostModifier(extraHeight: CodyMetrics.Conversation.topFadeExtraHeight))
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: clearance)
                }
        } else {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: clearance)
                        .background(alignment: .top) {
                            if clearance > 0 {
                                CodyEdgeFadeBar(direction: .bottom, height: CodyMetrics.Conversation.bottomFadeHeight)
                                    .offset(y: -CodyMetrics.Conversation.bottomFadeHeight)
                                    .allowsHitTesting(false)
                            }
                        }
                }
        }
    }
}
