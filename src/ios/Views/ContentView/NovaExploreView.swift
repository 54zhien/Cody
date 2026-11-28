import SwiftUI
import UIKit

struct NovaExploreView: View {
    @ObservedObject var tabStore: CodyNovaTabStore
    @ObservedObject var pinDragState: CodyNovaPinDragState
    let bottomClearance: CGFloat
    let onOpenDrawer: () -> Void
    let onSelectTool: (CodyNovaPinnedTool) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private var matchingTools: [CodyNovaPinnedTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CodyNovaPinnedTool.allCases }
        return CodyNovaPinnedTool.allCases.filter { tool in
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
        let isDraggingCard = pinDragState.draggingTool != nil
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
    }

    private var exploreScrollView: some View {
        ScrollView {
            let tools = matchingTools
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
        .scrollDisabled(pinDragState.draggingTool != nil)
    }

    private var header: some View {
        HStack {
            headerButton("Open sidebar", action: onOpenDrawer) {
                CodyDrawerGlyph(size: 24)
            }
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
        let isBeingDragged = pinDragState.draggingTool == tool

        return NovaExploreCardBody(tool: tool, isPinned: isPinned)
            .opacity(isBeingDragged ? 0.0 : 1.0)
            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isBeingDragged)
            .overlay {
                // UIKit scroll-safe tap + long-press-and-drag recognizer:
                // - Immediate vertical swipe passes straight through to UIScrollView (zero scroll lock).
                // - Short tap opens the tool.
                // - Holding still for 0.30s lifts the card and drags smoothly into the bottom tab bar.
                NovaExploreCardGestureOverlay(
                    onTap: {
                        guard pinDragState.draggingTool == nil else { return }
                        searchFocused = false
                        onSelectTool(tool)
                    },
                    onDragBegan: { point in
                        searchFocused = false
                        pinDragState.begin(tool: tool, at: point)
                    },
                    onDragChanged: { point in
                        pinDragState.update(location: point)
                    },
                    onDragEnded: {
                        withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                            pinDragState.end(pinInto: tabStore)
                        }
                    },
                    onDragCancelled: {
                        pinDragState.cancel()
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
            Text("Long-press and drag an item to the tab bar to pin")
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textTertiary)
                .multilineTextAlignment(.center)

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
/// immediate scroll movement (>10pt) and only claims the touch once held still for 0.30s.
private struct NovaExploreCardGestureOverlay: UIViewRepresentable {
    let onTap: () -> Void
    let onDragBegan: (CGPoint) -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onDragCancelled: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: NovaExploreCardGestureOverlay

        init(parent: NovaExploreCardGestureOverlay) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let window = recognizer.view?.window else {
                if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                    parent.onDragCancelled()
                }
                return
            }
            let location = recognizer.location(in: window)
            switch recognizer.state {
            case .began:
                parent.onDragBegan(location)
            case .changed:
                parent.onDragChanged(location)
            case .ended:
                parent.onDragEnded()
            case .cancelled, .failed:
                parent.onDragCancelled()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow UIScrollView's pan gesture to run freely unless our long press has already begun.
            if gestureRecognizer is UILongPressGestureRecognizer {
                return gestureRecognizer.state == .possible
            }
            return false
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
        longPress.delegate = context.coordinator

        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
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
