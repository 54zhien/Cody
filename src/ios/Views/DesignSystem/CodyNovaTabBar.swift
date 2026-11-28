import SwiftUI
import UIKit

/// Compact customizable icon-only bottom bar (`Home` · pinned custom tools · `More`).
///
/// Design rules:
/// - Centered compact layout: slots use a capped max width so removing tools pulls the remaining
///   icons inward toward the center instead of stretching them across the screen edges.
/// - At rest: selected tab uses a calm translucent Material capsule (`64×40`) — NOT an always-on
///   Liquid Glass bubble.
/// - While pressing and dragging horizontally across the bar: the indicator lifts into a live
///   iOS 26 Liquid Glass droplet that glides under the finger with haptic ticks and commits on release.
/// - Long-pressing a pinned custom tool lifts a clean capsule preview (`.contentShape(.contextMenuPreview, Capsule())`)
///   with an "Unpin from Tab Bar" menu action (never a rectangular white slab).
/// - While dragging an Explore card over the bar, smoothly inserts a live preview icon slot so the
///   centered bar expands outward to welcome the dropped tool.
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

    @State private var rowWidth: CGFloat = 0
    @State private var isScrubbing: Bool = false
    @State private var scrubX: CGFloat = 0
    @State private var lastScrubIndex: Int? = nil
    @State private var scrubHoveredDestination: CodyNovaDestination? = nil

    static let barHeight: CGFloat = 44
    /// Physical bottom screen-edge inset on Face ID iPhones (tucked right above the home indicator).
    static let physicalBottomInset: CGFloat = 18
    /// Total band height measured from the physical bottom screen edge.
    static let totalFromPhysicalBottom: CGFloat = barHeight + physicalBottomInset

    private static let restingPillWidth: CGFloat = 64
    private static let restingPillHeight: CGFloat = 40
    private static let scrubbingPillWidth: CGFloat = 72
    private static let scrubbingPillHeight: CGFloat = 44
    private static let maxSlotWidth: CGFloat = 78
    private static let slotSpacing: CGFloat = 4

    /// Height by which the bottom tab bar protrudes above the system bottom safe area.
    @MainActor
    static func safeAreaProtrusion(safeAreaBottom: CGFloat) -> CGFloat {
        let bottomInset = safeAreaBottom > 0 ? physicalBottomInset : 8
        return max(0, (barHeight + bottomInset) - safeAreaBottom)
    }

    private var allDestinations: [CodyNovaDestination] {
        var items: [CodyNovaDestination] = [.home]
        items.append(contentsOf: tabStore.pinnedTools.map { .tool($0) })
        items.append(.more)
        return items
    }

    /// Live preview tool inserted before `.more` when the user drags an unpinned Explore card over the bar.
    private var previewDropTool: CodyNovaPinnedTool? {
        guard pinDragState.isHoveringTabBar,
              let tool = pinDragState.draggingTool,
              !tabStore.isPinned(tool) else {
            return nil
        }
        return tool
    }

    var body: some View {
        let items = allDestinations
        let previewTool = previewDropTool
        let totalSlots = max(1, items.count + (previewTool != nil ? 1 : 0))

        GeometryReader { geo in
            let availableWidth = max(1, geo.size.width - 24)
            let slotWidth = min(
                Self.maxSlotWidth,
                (availableWidth - Self.slotSpacing * CGFloat(max(0, totalSlots - 1))) / CGFloat(totalSlots)
            )
            let clusterWidth = slotWidth * CGFloat(totalSlots) + Self.slotSpacing * CGFloat(max(0, totalSlots - 1))

            HStack {
                Spacer(minLength: 0)

                ZStack(alignment: .leading) {
                    if isScrubbing, rowWidth > 0 {
                        scrubbingDroplet
                            .position(x: scrubX, y: Self.barHeight / 2)
                            .allowsHitTesting(false)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }

                    HStack(spacing: Self.slotSpacing) {
                        ForEach(items) { dest in
                            if dest == .more, let previewTool {
                                dropPreviewSlot(for: previewTool, width: slotWidth)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                            tabSlot(for: dest, width: slotWidth)
                        }
                    }
                }
                .frame(width: clusterWidth, height: Self.barHeight)
                .coordinateSpace(name: "novaTabBarSpace")
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(newWidth - rowWidth) > 0.5 {
                        rowWidth = newWidth
                    }
                }
                .simultaneousGesture(scrubGesture(items: items))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.barHeight)
        }
        .frame(height: Self.barHeight)
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
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: tabStore.pinnedTools)
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: previewTool)
        .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isScrubbing)
    }

    private func dropPreviewSlot(for tool: CodyNovaPinnedTool, width: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                .frame(width: min(Self.restingPillWidth, width), height: Self.restingPillHeight)
            CodyIconView(systemName: tool.iconName, size: 27)
                .foregroundStyle(CodyColors.iconPrimary.opacity(0.85))
        }
        .frame(width: width, height: Self.barHeight)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func tabSlot(for dest: CodyNovaDestination, width: CGFloat) -> some View {
        let isSelected = (selection == dest)
        let isVisuallyActive = isScrubbing ? (scrubHoveredDestination == dest) : isSelected
        let pillWidth = min(Self.restingPillWidth, width)

        let capsuleLabel = ZStack {
            if isSelected && !isScrubbing {
                restingMaterialPill(width: pillWidth)
                    .matchedGeometryEffect(id: "novaRestingTabPill", in: activeIndicatorNamespace)
            }

            tabIcon(for: dest, selected: isVisuallyActive)
                .foregroundStyle(isVisuallyActive ? CodyColors.iconPrimary : CodyColors.iconSecondary)
        }
        .frame(width: pillWidth, height: Self.restingPillHeight)
        .contentShape(Capsule())
        .contentShape(.contextMenuPreview, Capsule())

        let button = Button {
            guard !isScrubbing else { return }
            if isSelected {
                onReselect?(dest)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
                select(dest)
            }
        } label: {
            capsuleLabel
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(accessibilityLabel(for: dest))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

        Group {
            if case .tool(let tool) = dest {
                button
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
                button
            }
        }
        .frame(width: width, height: Self.barHeight)
    }

    /// Calm frosted Material pill at rest (matches Screenshot 2 & 6).
    private func restingMaterialPill(width: CGFloat) -> some View {
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
        .frame(width: width, height: Self.restingPillHeight)
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

    private func scrubGesture(items: [CodyNovaDestination]) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("novaTabBarSpace"))
            .onChanged { value in
                let count = items.count
                guard rowWidth > 0, count > 0 else { return }
                if !isScrubbing {
                    guard abs(value.translation.width) >= 6,
                          abs(value.translation.width) >= abs(value.translation.height) * 0.65 else {
                        return
                    }
                    isScrubbing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                let slotWidth = rowWidth / CGFloat(count)
                let clampedX = min(max(value.location.x, slotWidth / 2), rowWidth - slotWidth / 2)
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
            CodyIconView(selected ? .homeFilled : .home, size: 27)
        case .tool(let tool):
            CodyIconView(systemName: selected ? tool.selectedIconName : tool.iconName, size: 27)
        case .more:
            CodyIconView(selected ? .moreFilled : .more, size: 26)
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
