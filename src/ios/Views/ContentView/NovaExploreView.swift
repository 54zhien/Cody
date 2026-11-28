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
    @State private var cardFrames: [CodyNovaPinnedTool: CGRect] = [:]
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
        Group {
            if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive {
                exploreScrollView
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    .safeAreaBar(edge: .top, spacing: 0) {
                        header
                    }
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        footer
                            .padding(.bottom, bottomClearance)
                    }
            } else {
                exploreScrollView
                    .safeAreaInset(edge: .top, spacing: 0) {
                        header
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        footer
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
                CodyDrawerGlyph(size: 20)
            }
            Spacer()
            headerButton("Settings", action: onOpenSettings) {
                CodyIconView(.settings, size: 21)
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
        let dragToPin = LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let drag):
                    searchFocused = false
                    let fallbackCenter: CGPoint = {
                        if let rect = cardFrames[tool] {
                            return CGPoint(x: rect.midX, y: rect.midY)
                        }
                        return drag?.location ?? .zero
                    }()
                    let point = drag?.location ?? fallbackCenter
                    if pinDragState.draggingTool != tool {
                        pinDragState.begin(tool: tool, at: point)
                    } else {
                        pinDragState.update(location: point)
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, _) = value {
                    withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                        pinDragState.end(pinInto: tabStore)
                    }
                } else if pinDragState.draggingTool == tool {
                    pinDragState.cancel()
                }
            }

        return NovaExploreCardBody(tool: tool, isPinned: isPinned)
            .opacity(isBeingDragged ? 0.28 : 1.0)
            .scaleEffect(isBeingDragged ? 0.96 : 1.0)
            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isBeingDragged)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { rect in
                cardFrames[tool] = rect
            }
            .onTapGesture {
                guard pinDragState.draggingTool == nil else { return }
                searchFocused = false
                onSelectTool(tool)
            }
            .simultaneousGesture(dragToPin)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(tool.title))
            .accessibilityValue(isPinned ? Text("Pinned") : Text(""))
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
                CodyIconView(.search, size: 19)
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

            CodyIconView(systemName: tool.iconName, size: 28)
                .foregroundStyle(tool.exploreGlyphColor)
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
