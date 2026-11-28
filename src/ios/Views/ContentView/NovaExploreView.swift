import SwiftUI
import UIKit

struct NovaExploreView: View {
    @ObservedObject var tabStore: CodyNovaTabStore
    @ObservedObject var pinDragState: CodyNovaPinDragState
    let bottomClearance: CGFloat
    let isWide: Bool
    let transitionNamespace: Namespace.ID
    let onReturnToChat: () -> Void
    let onOpenDrawer: () -> Void
    let onSelectTool: (CodyNovaPinnedTool) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("cody.nova.hasPinnedExploreTool") private var hasPinnedExploreTool = false
    @State private var didTriggerPull = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : (isWide ? 3 : 2)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private var isSearching: Bool { searchFocused || !searchText.isEmpty }

    private var matchingTools: [CodyNovaPinnedTool] {
        let order = pinDragState.previewOrder ?? tabStore.exploreOrder
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return order }
        return order.filter { tool in
            let titles = searchTitles(for: tool)
            return titles.localized.localizedStandardContains(query)
                || titles.english.localizedStandardContains(query)
                || tool.rawValue.localizedStandardContains(query)
        }
    }

    private func searchTitles(for tool: CodyNovaPinnedTool) -> (localized: String, english: String) {
        switch tool {
        case .files: (AppLocalized("Files"), "Files")
        case .terminal: (AppLocalized("Terminal"), "Terminal")
        case .skills: (AppLocalized("Skills"), "Skills")
        case .mcp: (AppLocalized("MCP"), "MCP")
        case .browser: (AppLocalized("Browser"), "Browser")
        case .agentTools: (AppLocalized("Agent Tools"), "Agent Tools")
        case .subAgents: (AppLocalized("Sub Agents"), "Sub Agents")
        case .soul: (AppLocalized("Soul"), "Soul")
        case .memory: (AppLocalized("Memory"), "Memory")
        case .providers: (AppLocalized("Providers"), "Providers")
        case .usage: (AppLocalized("Usage"), "Usage")
        case .alarms: (AppLocalized("Alarms"), "Alarms")
        }
    }

    var body: some View {
        let isDraggingCard = pinDragState.hasLiftedCard
        Group {
            if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive {
                exploreScrollView
                    .modifier(CodyTopScrollEdgeHostModifier(extraHeight: CodyControlHeight.standard))
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    .safeAreaBar(edge: .top, spacing: 0) {
                        header
                    }
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        footer
                            .opacity(isDraggingCard ? 0 : 1)
                            .allowsHitTesting(!isDraggingCard)
                            .padding(.bottom, bottomClearance)
                            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isDraggingCard)
                    }
            } else {
                exploreScrollView
                    .safeAreaInset(edge: .top, spacing: 0) {
                        header
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        footer
                            .opacity(isDraggingCard ? 0 : 1)
                            .allowsHitTesting(!isDraggingCard)
                            .padding(.bottom, bottomClearance)
                            .background(alignment: .top) {
                                VStack(spacing: 0) {
                                    CodyEdgeFadeBar(direction: .bottom, height: CodyMetrics.Conversation.bottomFadeHeight)
                                    CodyColors.bgCanvas
                                }
                                .offset(y: -CodyMetrics.Conversation.bottomFadeHeight)
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                            }
                            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isDraggingCard)
                    }
            }
        }
        .background(CodyColors.bgCanvas.ignoresSafeArea())
        .onChange(of: tabStore.pinnedTools) { [previous = tabStore.pinnedTools] current in
            if current.contains(where: { !previous.contains($0) }) { hasPinnedExploreTool = true }
        }
        .onDisappear {
            pinDragState.reset()
            pinDragState.cardFrames.removeAll()
        }
    }

    @ViewBuilder
    private var exploreScrollView: some View {
        if #available(iOS 18.0, *) {
            exploreScrollContent
                .scrollBounceBehavior(.always)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, -geometry.contentOffset.y - geometry.contentInsets.top)
                } action: { _, distance in
                    handlePull(distance)
                }
        } else {
            exploreScrollContent
                .coordinateSpace(name: "codyExploreScroll")
        }
    }

    private var exploreScrollContent: some View {
        ScrollView {
            if #unavailable(iOS 18.0) {
                Color.clear.frame(height: 0)
                    .onGeometryChange(for: CGFloat.self) {
                        max(0, $0.frame(in: .named("codyExploreScroll")).minY)
                    } action: { distance in
                        handlePull(distance)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            let tools = matchingTools
            if isSearching {
                HStack {
                    Text("Search Results")
                        .font(CodyTypography.titleSmall)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") {
                        searchText = ""
                        searchFocused = false
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, CodySpacing.sm)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -8)))
            }
            if tools.isEmpty {
                Text("No matching tools")
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, CodySpacing.xl)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tools) { tool in
                        toolCard(tool)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, CodySpacing.sm)
                .padding(.bottom, CodySpacing.lg)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isSearching)
    }

    private func handlePull(_ distance: CGFloat) {
        if distance < 10 { didTriggerPull = false }
        guard distance >= 78, !didTriggerPull, !isSearching, pinDragState.draggingTool == nil else { return }
        didTriggerPull = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onReturnToChat()
    }

    private var header: some View {
        HStack {
            headerButton("Open sidebar", action: onOpenDrawer) {
                CodyDrawerGlyph(size: 24)
            }
            .modifier(CodyDrawerAccessibility())
            Spacer()
            headerButton("Settings", action: onOpenSettings) {
                CodyIconView(.settings, size: 25)
                    .foregroundStyle(CodyColors.iconPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, CodySpacing.xsPlus)
    }

    /// Apple HIG standard 44×44pt circular Liquid Glass control button (iOS 26+),
    /// with elevated hairline-bordered circle fallback on earlier systems.
    private func headerButton<Glyph: View>(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        Button {
            searchFocused = false
            action()
        } label: {
            glyph()
                .frame(width: CodyControlHeight.standard, height: CodyControlHeight.standard)
                .modifier(NovaExploreGlassCircle(reduceTransparency: reduceTransparency))
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(Text(title))
    }

    private func toolCard(_ tool: CodyNovaPinnedTool) -> some View {
        let isPinned = tabStore.isPinned(tool)
        let isBeingDragged = pinDragState.draggingTool == tool && pinDragState.hasLiftedCard

        return NovaExploreCardBody(tool: tool, isPinned: isPinned)
            .opacity(isBeingDragged ? 0.0 : 1.0)
            .background {
                if isBeingDragged {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(CodyColors.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .modifier(ComposerZoomSourceModifier(id: tool.rawValue, namespace: transitionNamespace))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                pinDragState.cardFrames[tool] = $0
            }
            .onDisappear { pinDragState.cardFrames[tool] = nil }
            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isBeingDragged)
            .overlay {
                // UIKit scroll-safe tap + long-press-and-drag recognizer:
                // - Immediate vertical swipe passes straight through to UIScrollView (zero scroll lock).
                // - Short tap opens the tool.
                // - Holding enters editing. Movement then lifts the card into the drag overlay.
                NovaExploreCardGestureOverlay(
                    onTap: {
                        guard pinDragState.draggingTool == nil else { return }
                        searchFocused = false
                        onSelectTool(tool)
                    },
                    onDragBegan: { point, frame in
                        pinDragState.begin(tool: tool, at: point, frame: frame, order: tabStore.exploreOrder)
                    },
                    onDragChanged: { point in
                        pinDragState.update(location: point, pinned: tabStore.pinnedTools,
                                            reduceMotion: reduceMotion, allowsReordering: !isSearching)
                        if pinDragState.hasLiftedCard { searchFocused = false }
                    },
                    onDragEnded: { point in
                        pinDragState.end(at: point, in: tabStore, reduceMotion: reduceMotion,
                                         allowsReordering: !isSearching)
                    },
                    onDragCancelled: {
                        if pinDragState.draggingTool == tool {
                            pinDragState.cancel(reduceMotion: reduceMotion)
                        }
                    }
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(tool.title))
            .accessibilityValue(isPinned ? Text("Pinned") : Text(""))
            .accessibilityAction {
                searchFocused = false
                onSelectTool(tool)
            }
            .accessibilityAction(named: isPinned ? Text("Unpin from Tab Bar") : Text("Pin to Tab Bar")) {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                    tabStore.togglePin(tool)
                }
            }
    }

    private var footer: some View {
        VStack(spacing: CodySpacing.xsPlus) {
            if let tool = pinDragState.draggingTool,
               !tabStore.isPinned(tool), tabStore.pinnedTools.count >= CodyNovaTabStore.maxPinnedCount {
                Text("Tab bar is full. Unpin a tool to make room.")
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .multilineTextAlignment(.center)
            } else if !hasPinnedExploreTool && tabStore.pinnedTools.count < CodyNovaTabStore.maxPinnedCount && !isSearching {
                Text("Long-press and drag an item to the tab bar to pin")
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: CodySpacing.sm) {
                CodyIconView(.search, size: 23)
                    .foregroundStyle(CodyColors.iconPrimary)
                    .frame(width: 36)
                    .accessibilityHidden(true)

                TextField("Search", text: $searchText)
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }

                if searchText.isEmpty {
                    Color.clear.frame(width: 36)
                        .accessibilityHidden(true)
                } else {
                    Button { searchText = "" } label: {
                        CodyIconView(.close, size: 16)
                            .foregroundStyle(CodyColors.iconSecondary)
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, CodySpacing.sm)
            .frame(height: 48)
            .modifier(NovaExploreGlassCapsule(reduceTransparency: reduceTransparency))
        }
        .padding(.horizontal, 16)
        .padding(.top, CodySpacing.xs)
        .padding(.bottom, CodySpacing.xsPlus)
    }
}

/// Scroll-safe UIKit gesture bridge for Explore cards.
/// Unlike SwiftUI `LongPressGesture.sequenced(before: DragGesture(minimumDistance: 0))` — which blocks
/// `UIScrollView` panning inside a `ScrollView` — `UILongPressGestureRecognizer` fails cleanly on
/// immediate scroll movement and only claims the touch once held still for 0.35s.
private struct NovaExploreCardGestureOverlay: UIViewRepresentable {
    let onTap: () -> Void
    let onDragBegan: (CGPoint, CGRect) -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    let onDragCancelled: () -> Void

    final class Coordinator: NSObject {
        var parent: NovaExploreCardGestureOverlay
        private weak var suspendedPan: UIPanGestureRecognizer?
        private var ownsDrag = false

        init(parent: NovaExploreCardGestureOverlay) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view, let window = view.window else {
                finishTracking(cancelled: true)
                return
            }
            let location = recognizer.location(in: window)
            switch recognizer.state {
            case .began:
                ownsDrag = true
                // Stop only the parent pan after UIKit recognizes the hold.
                // Changing the ScrollView's SwiftUI scroll state mid-touch can
                // reset the gesture before the drag receives its release.
                var ancestor = view.superview
                while let candidate = ancestor {
                    if let scrollView = candidate as? UIScrollView {
                        let pan = scrollView.panGestureRecognizer
                        if pan.isEnabled {
                            suspendedPan = pan
                            pan.isEnabled = false
                        }
                        break
                    }
                    ancestor = candidate.superview
                }
                parent.onDragBegan(location, view.convert(view.bounds, to: window))
            case .changed where ownsDrag:
                parent.onDragChanged(location)
            case .ended where ownsDrag:
                parent.onDragEnded(location)
                finishTracking(cancelled: false)
            case .cancelled, .failed:
                finishTracking(cancelled: true)
            default:
                break
            }
        }

        func finishTracking(cancelled: Bool) {
            guard ownsDrag else { return }
            ownsDrag = false
            suspendedPan?.isEnabled = true
            suspendedPan = nil
            if cancelled { parent.onDragCancelled() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = CodyMotion.longPressDuration
        longPress.allowableMovement = CodyMotion.longPressAllowableMovement
        longPress.cancelsTouchesInView = false

        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.finishTracking(cancelled: true)
        }
    }
}

/// Shared card body used both inside the Explore grid and as the floating drag snapshot.
struct NovaExploreCardBody: View {
    let tool: CodyNovaPinnedTool
    let isPinned: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: CodySpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CodySpacing.xs) {
                Text(tool.title)
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isPinned {
                    Circle()
                        .fill(tool.exploreGlyphColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)

            CodyExploreIconView(tool.exploreColorIcon, size: 34)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 108, alignment: .topLeading)
        .background {
            shape.fill(CodySettingsHairline.cardFill)
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        }
        .overlay {
            shape.strokeBorder(CodySettingsHairline.strokeColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
    }
}

private struct NovaExploreGlassCircle: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            content
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        } else {
            content
                .background(CodySettingsHairline.cardFill, in: Circle())
                .overlay {
                    Circle().strokeBorder(CodySettingsHairline.strokeColor, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
        }
    }
}

private struct NovaExploreGlassCapsule: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(Capsule())
        } else {
            content
                .background(CodySettingsHairline.cardFill, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(CodySettingsHairline.strokeColor, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
    }
}
