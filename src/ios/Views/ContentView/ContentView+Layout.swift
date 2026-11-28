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
            novaTabShell {
                switch novaDestination {
                case .home: detailView
                case .more: novaExploreNavigation(isWide: true)
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
        let visibleRoute = isWideLayout ? selectedSessionId : currentStackSessionId
        let activeId = novaDestination == .home ? visibleRoute.flatMap { persistedSessionId(for: $0) } : nil
        return sidebarBadgeStore.unreadSessionIds.contains { $0 != activeId }
    }

    var stackLayout: some View {
        CodySidebarDrawer(isOpen: $isNovaDrawerOpen, edgeDragEnabled: !isSelecting && navigationPath.isEmpty) {
            novaTabShell {
                novaDestinationContent
                    .accessibilityHidden(isNovaDrawerOpen)
            }
        } drawer: {
            novaDrawer
        }
    }

    private func novaTabShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .environment(\.novaSidebarHasUnread, novaSidebarHasUnread)
            .overlay(alignment: .bottom) {
                if showNovaTabBar {
                    CodyNovaTabBar(
                        selection: $novaDestination,
                        tabStore: novaTabStore,
                        pinDragState: novaPinDragState,
                        onSelectDestination: selectNovaDestination,
                        onReselect: { destination in
                            if destination == .more { novaExplorePath.removeAll() }
                            if destination == .home {
                                if isWideLayout { columnVisibility = .all } else { openNovaDrawer() }
                            }
                        }
                    )
                    .accessibilityHidden(isNovaDrawerOpen)
                    .allowsHitTesting(!isNovaDrawerOpen)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if let tool = novaPinDragState.draggingTool {
                    NovaToolDragPreview(
                        tool: tool,
                        isPinned: novaTabStore.isPinned(tool),
                        state: novaPinDragState
                    )
                }
            }
            .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: showNovaTabBar)
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
            novaExploreNavigation(isWide: false)
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

    private func novaExploreNavigation(isWide: Bool) -> some View {
        NavigationStack(path: $novaExplorePath) {
            NovaExploreView(
                tabStore: novaTabStore,
                pinDragState: novaPinDragState,
                bottomClearance: novaBottomClearance,
                isWide: isWide,
                transitionNamespace: novaExploreTransition,
                onReturnToChat: { selectNovaDestination(.home) },
                onOpenDrawer: isWide ? { columnVisibility = .all } : openNovaDrawer,
                onSelectTool: openExploreTool,
                onOpenSettings: { activeToolSheet = .settings }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CodyNovaPinnedTool.self) { tool in
                if #available(iOS 18.0, *), !reduceMotion {
                    novaTool(tool, isWide: isWide)
                        .navigationTransition(.zoom(sourceID: tool.rawValue, in: novaExploreTransition))
                } else {
                    novaTool(tool, isWide: isWide)
                }
            }
        }
    }

    private func openExploreTool(_ tool: CodyNovaPinnedTool) {
        switch tool {
        case .terminal, .browser:
            selectNovaDestination(.tool(tool))
        case .alarms where alarmkit_is_usable():
            selectNovaDestination(.tool(tool))
        default:
            novaExplorePath.append(tool)
        }
    }

    private func novaTool(_ tool: CodyNovaPinnedTool, isWide: Bool) -> some View {
        let clearance = novaBottomClearance
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
        case .subAgents: HelperSettingsView(showsRunActivity: true)
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
                .environment(\.novaTabBarBottomInset, novaBottomClearance)
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

private struct NovaToolDragPreview: View {
    let tool: CodyNovaPinnedTool
    let isPinned: Bool
    @ObservedObject var state: CodyNovaPinDragState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let landing = state.landingFrame
            let point = landing.map { CGPoint(x: $0.midX, y: $0.midY) } ?? state.dragLocation
            let showsIcon = landing == nil ? state.isHoveringTabBar : state.isLandingOnBar
            let width = state.cardFrames[tool]?.width ?? 164

            ZStack {
                NovaExploreCardBody(tool: tool, isPinned: isPinned)
                    .frame(width: width)
                    .scaleEffect(showsIcon ? 0.24 : 1)
                    .opacity(showsIcon ? 0 : 1)
                    .shadow(color: .black.opacity(0.20), radius: 16, y: 8)

                CodyIconView(systemName: tool.iconName, size: 27)
                    .foregroundStyle(CodyColors.iconPrimary)
                    .scaleEffect(showsIcon ? 1 : 0.65)
                    .opacity(showsIcon ? 1 : 0)
            }
            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: showsIcon)
            .position(x: point.x - origin.x, y: point.y - origin.y)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    .modifier(CodyDrawerAccessibility())
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
