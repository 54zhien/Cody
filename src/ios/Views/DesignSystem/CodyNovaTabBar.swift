import SwiftUI
import UIKit

/// Compact customizable icon-only bottom bar (`Home` · pinned custom tools · `More`).
///
/// Design rules:
/// - At rest: selected tab uses a calm translucent Material capsule (matching the Nova reference
///   proportions, spacing, and bottom alignment) — NOT an always-on Liquid Glass bubble.
/// - While pressing and dragging across the bar: the indicator lifts and morphs into a live
///   iOS 26 Liquid Glass droplet that glides smoothly under the user's finger with selection haptics,
///   then settles back into the resting Material capsule on release.
/// - Pinned custom tools support long-press `.contextMenu` to unpin directly from the bottom bar.
/// - Acts as a live drop target for Explore cards dragged down onto the bar.
struct CodyNovaTabBar: View {
    @Binding var selection: CodyNovaDestination
    @ObservedObject var tabStore: CodyNovaTabStore
    @ObservedObject var pinDragState: CodyNovaPinDragState
    var onSelectDestination: ((CodyNovaDestination) -> Void)? = nil
    var onReselect: ((CodyNovaDestination) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var activeIndicatorNamespace

    @State private var barWidth: CGFloat = 0
    @State private var isScrubbing: Bool = false
    @State private var scrubX: CGFloat = 0
    @State private var lastScrubIndex: Int? = nil
    @State private var scrubHoveredDestination: CodyNovaDestination? = nil

    static let barHeight: CGFloat = 48
    static let bottomPadding: CGFloat = 2
    static let totalClearance: CGFloat = barHeight + bottomPadding

    private static let restingPillWidth: CGFloat = 64
    private static let restingPillHeight: CGFloat = 42
    private static let scrubbingPillWidth: CGFloat = 74
    private static let scrubbingPillHeight: CGFloat = 46

    private var allDestinations: [CodyNovaDestination] {
        var items: [CodyNovaDestination] = [.home]
        items.append(contentsOf: tabStore.pinnedTools.map { .tool($0) })
        items.append(.more)
        return items
    }

    var body: some View {
        let items = allDestinations
        let count = max(1, items.count)
        let isDropHover = pinDragState.isHoveringTabBar
        let isDraggingFromExplore = pinDragState.draggingTool != nil

        ZStack {
            if isDraggingFromExplore {
                dropZoneBackdrop(highlighted: isDropHover)
            }

            ZStack(alignment: .leading) {
                // Live Liquid Glass droplet shown ONLY while actively scrubbing across the bar
                if isScrubbing, barWidth > 0 {
                    scrubbingDroplet
                        .position(x: scrubX, y: Self.barHeight / 2)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    ForEach(items) { dest in
                        tabSlot(for: dest)
                    }
                }
            }
            .coordinateSpace(name: "novaTabBarSpace")
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                if abs(newWidth - barWidth) > 0.5 {
                    barWidth = newWidth
                }
            }
            .simultaneousGesture(scrubGesture(items: items, count: count))
        }
        .frame(height: Self.barHeight)
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomPadding)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            if abs(frame.minY - pinDragState.tabBarFrame.minY) > 1
                || abs(frame.width - pinDragState.tabBarFrame.width) > 1 {
                pinDragState.tabBarFrame = frame
            }
        }
        .onDisappear {
            isScrubbing = false
            lastScrubIndex = nil
            scrubHoveredDestination = nil
        }
        .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isScrubbing)
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isDropHover)
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isDraggingFromExplore)
    }

    @ViewBuilder
    private func tabSlot(for dest: CodyNovaDestination) -> some View {
        let isSelected = (selection == dest)
        let isVisuallyActive = isScrubbing ? (scrubHoveredDestination == dest) : isSelected
        let baseButton = Button {
            guard !isScrubbing else { return }
            if isSelected {
                onReselect?(dest)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
                select(dest)
            }
        } label: {
            ZStack {
                if isSelected && !isScrubbing {
                    restingMaterialPill
                        .matchedGeometryEffect(id: "novaRestingTabPill", in: activeIndicatorNamespace)
                }

                tabIcon(for: dest, selected: isVisuallyActive)
                    .foregroundStyle(isVisuallyActive ? CodyColors.iconPrimary : CodyColors.iconSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.barHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(accessibilityLabel(for: dest))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

        if case .tool(let tool) = dest {
            baseButton
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                            if selection == .tool(tool) {
                                select(.home)
                            }
                            tabStore.unpin(tool)
                        }
                    } label: {
                        Label("Unpin from Tab Bar", systemImage: "pin.slash")
                    }
                }
        } else {
            baseButton
        }
    }

    /// Calm frosted Material pill at rest (matches Screenshot 3 — soft translucent surface, no glass rim).
    private var restingMaterialPill: some View {
        Group {
            if reduceTransparency {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.09))
            } else {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    }
            }
        }
        .frame(width: Self.restingPillWidth, height: Self.restingPillHeight)
    }

    /// Interactive iOS 26 Liquid Glass droplet shown exclusively while pressing & sliding across the bottom bar.
    @ViewBuilder
    private var scrubbingDroplet: some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            Color.clear
                .frame(width: Self.scrubbingPillWidth, height: Self.scrubbingPillHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(CodyColors.borderDefault, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
                .frame(width: Self.scrubbingPillWidth, height: Self.scrubbingPillHeight)
        }
    }

    @ViewBuilder
    private func dropZoneBackdrop(highlighted: Bool) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            Capsule()
                .fill(highlighted ? CodyColors.textAccent.opacity(0.18) : Color.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            highlighted ? CodyColors.textAccent.opacity(0.75) : CodyColors.borderDefault,
                            style: StrokeStyle(lineWidth: highlighted ? 1.5 : 1, dash: highlighted ? [] : [5, 4])
                        )
                }
                .frame(height: Self.barHeight)
                .allowsHitTesting(false)
        } else {
            Capsule()
                .fill(highlighted ? CodyColors.textAccent.opacity(0.18) : CodyColors.bgSecondary.opacity(0.85))
                .overlay {
                    Capsule()
                        .strokeBorder(
                            highlighted ? CodyColors.textAccent : CodyColors.borderDefault,
                            lineWidth: highlighted ? 1.5 : 1
                        )
                }
                .frame(height: Self.barHeight)
                .allowsHitTesting(false)
        }
    }

    private func scrubGesture(items: [CodyNovaDestination], count: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("novaTabBarSpace"))
            .onChanged { value in
                guard barWidth > 0, !items.isEmpty else { return }
                if !isScrubbing {
                    guard abs(value.translation.width) >= 6,
                          abs(value.translation.width) >= abs(value.translation.height) * 0.65 else {
                        return
                    }
                    isScrubbing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                let slotWidth = barWidth / CGFloat(count)
                let clampedX = min(max(value.location.x, slotWidth / 2), barWidth - slotWidth / 2)
                scrubX = clampedX

                let idx = min(max(Int(clampedX / slotWidth), 0), count - 1)
                if idx != lastScrubIndex {
                    lastScrubIndex = idx
                    scrubHoveredDestination = items[idx]
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                if isScrubbing {
                    let target = scrubHoveredDestination
                    withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                        isScrubbing = false
                    }
                    lastScrubIndex = nil
                    scrubHoveredDestination = nil
                    if let target, target != selection {
                        select(target)
                    }
                }
            }
    }

    private func select(_ dest: CodyNovaDestination) {
        if let onSelectDestination {
            onSelectDestination(dest)
        } else {
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                selection = dest
            }
        }
    }

    @ViewBuilder
    private func tabIcon(for dest: CodyNovaDestination, selected: Bool) -> some View {
        switch dest {
        case .home:
            CodyIconView(selected ? .homeFilled : .home, size: 24)
        case .tool(let tool):
            CodyIconView(systemName: selected ? tool.selectedIconName : tool.iconName, size: 24)
        case .more:
            CodyIconView(selected ? .moreFilled : .more, size: 23)
        }
    }

    private func accessibilityLabel(for dest: CodyNovaDestination) -> Text {
        switch dest {
        case .home: Text("Home")
        case .tool(let tool): Text(tool.title)
        case .more: Text("More")
        }
    }
}
