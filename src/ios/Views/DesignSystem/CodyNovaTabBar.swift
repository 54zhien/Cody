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
    @ObservedObject private var jobs = AgentJobRegistry.shared
    var onSelectDestination: ((CodyNovaDestination) -> Void)? = nil
    var onReselect: ((CodyNovaDestination) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var activeIndicatorNamespace

    private struct PinLift {
        var tool: CodyNovaPinnedTool
        var translation: CGSize
    }

    @GestureState private var pinLift: PinLift?
    @State private var unpinMenuTool: CodyNovaPinnedTool?
    @State private var rowWidth: CGFloat = 0
    @State private var isScrubbing: Bool = false
    @State private var scrubX: CGFloat = 0
    @State private var lastScrubIndex: Int? = nil
    @State private var scrubHoveredDestination: CodyNovaDestination? = nil

    static let barHeight: CGFloat = 44
    static let bottomPadding: CGFloat = 0
    /// Total height reserved above the system bottom safe area so the Composer never overlaps the bar.
    static let totalClearance: CGFloat = barHeight + bottomPadding

    private static let restingPillMinWidth: CGFloat = 48
    private static let restingPillWidth: CGFloat = 62
    private static let restingPillHeight: CGFloat = 38
    private static let scrubbingPillWidth: CGFloat = 70
    private static let scrubbingPillHeight: CGFloat = 42
    private static let minSlotWidth: CGFloat = 48
    private static let maxSlotWidth: CGFloat = 74
    private static let slotSpacing: CGFloat = 4

    private var subAgentActivity: SubAgentActivity? {
        jobs.subAgentActivities.values.max { $0.rawValue < $1.rawValue }
    }

    private var allDestinations: [CodyNovaDestination] {
        var items: [CodyNovaDestination] = [.home]
        items.append(contentsOf: tabStore.pinnedTools.map { .tool($0) })
        items.append(.more)
        return items
    }

    var body: some View {
        let items = allDestinations
        let pinnedWithoutPreview = tabStore.pinnedTools.filter { $0 != pinDragState.draggingTool }
        let preview = pinDragState.insertionIndex.flatMap { index in
            pinDragState.draggingTool.map { (tool: $0, index: min(index, pinnedWithoutPreview.count)) }
        }

        HStack(spacing: Self.slotSpacing) {
            if let preview {
                tabSlot(for: .home)
                ForEach(Array(pinnedWithoutPreview.enumerated()), id: \.element) { index, tool in
                    if preview.index == index { dropPreviewSlot(for: preview.tool) }
                    tabSlot(for: .tool(tool))
                }
                if preview.index == pinnedWithoutPreview.count { dropPreviewSlot(for: preview.tool) }
                tabSlot(for: .more)
            } else {
                ForEach(items) { tabSlot(for: $0) }
            }
        }
        .frame(height: Self.barHeight)
        .background {
            if isScrubbing, rowWidth > 0 {
                scrubbingDroplet
                    .position(x: scrubX, y: Self.barHeight / 2)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "novaTabBarSpace")
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if abs(newWidth - rowWidth) > 0.5 {
                rowWidth = newWidth
            }
        }
        .simultaneousGesture(scrubGesture(items: items))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            pinDragState.tabBarFrame = $0
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .padding(.bottom, Self.bottomPadding)
        .onDisappear {
            pinDragState.tabBarFrame = .zero
            pinDragState.tabFrames.removeAll()
            isScrubbing = false
            lastScrubIndex = nil
            scrubHoveredDestination = nil
        }
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: tabStore.pinnedTools)
        .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isScrubbing)
    }

    private func dropPreviewSlot(for tool: CodyNovaPinnedTool) -> some View {
        ZStack {
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                .frame(minWidth: Self.restingPillMinWidth, maxWidth: Self.restingPillWidth)
                .frame(height: Self.restingPillHeight)
            CodyIconView(systemName: tool.iconName, size: 27)
                .opacity(0)
        }
        .frame(minWidth: Self.minSlotWidth, maxWidth: Self.maxSlotWidth)
        .frame(height: Self.barHeight)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            pinDragState.previewFrame = $0
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tabSlot(for dest: CodyNovaDestination) -> some View {
        let isSelected = (selection == dest)
        let isVisuallyActive = isScrubbing ? (scrubHoveredDestination == dest) : isSelected
        let activity = dest == .tool(.subAgents) ? subAgentActivity : nil
        let showsActivity = activity != nil && !isScrubbing

        let capsuleLabel = ZStack {
            if isSelected && !isScrubbing {
                restingMaterialPill
                    .scaleEffect(x: showsActivity ? 1.04 : 1, y: showsActivity ? 1.08 : 1)
                    .matchedGeometryEffect(id: "novaRestingTabPill", in: activeIndicatorNamespace)
            }

            tabIcon(for: dest, selected: isVisuallyActive)
                .foregroundStyle(isVisuallyActive ? CodyColors.iconPrimary : CodyColors.iconSecondary)
                .modifier(CodyTabActivityMark(activity: isScrubbing ? nil : activity))
        }
        .frame(minWidth: Self.restingPillMinWidth, maxWidth: Self.restingPillWidth)
        .frame(height: Self.restingPillHeight)
        .background {
            if dest == .tool(.subAgents) {
                Capsule()
                    .fill(CodyColors.interactiveSecondaryBg)
                    .frame(width: showsActivity ? 60 : 42, height: showsActivity ? 38 : 30)
                    .opacity(showsActivity && !isSelected ? 1 : 0)
            }
        }
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: activity)
        .contentShape(Capsule())

        let button = Button {
            guard !isScrubbing, pinLift == nil else { return }
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
        .accessibilityValue(Text(activity?.title ?? ""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

        Group {
            if case .tool(let tool) = dest {
                button
                    .scaleEffect(pinLift?.tool == tool && !reduceMotion ? 1.12 : 1)
                    .offset(y: pinLift?.tool == tool && !reduceMotion
                            ? min(38, max(0, pinLift?.translation.height ?? 0)) : 0)
                    .modifier(PinnedTabEditingMotion(
                        isEditing: pinDragState.draggingTool != nil && !reduceMotion
                    ))
                    .simultaneousGesture(unpinGesture(for: tool))
                    .accessibilityAction(named: Text("Unpin from Tab Bar")) { unpin(tool) }
                    .popover(isPresented: Binding(
                        get: { unpinMenuTool == tool },
                        set: { if !$0, unpinMenuTool == tool { unpinMenuTool = nil } }
                    )) {
                        if #available(iOS 16.4, *) {
                            unpinMenuButton(for: tool).presentationCompactAdaptation(.popover)
                        } else {
                            unpinMenuButton(for: tool)
                        }
                    }
            } else {
                button
            }
        }
        .frame(minWidth: Self.minSlotWidth, maxWidth: Self.maxSlotWidth)
        .frame(height: Self.barHeight)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            pinDragState.tabFrames[dest] = $0
        }
    }

    private func unpinGesture(for tool: CodyNovaPinnedTool) -> some Gesture {
        LongPressGesture(minimumDuration: CodyMotion.longPressDuration,
                         maximumDistance: CodyMotion.longPressAllowableMovement)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($pinLift) { value, lift, transaction in
                if case .second(true, let drag) = value, !isScrubbing, pinDragState.draggingTool == nil {
                    transaction.animation = CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion)
                    lift = PinLift(tool: tool, translation: drag?.translation ?? .zero)
                }
            }
            .onEnded { value in
                guard !isScrubbing, pinDragState.draggingTool == nil else { return }
                guard case .second(true, let drag) = value else { return }
                let offset = drag?.translation ?? .zero
                if offset.height > 28 && offset.height > abs(offset.width) {
                    unpin(tool)
                } else if hypot(offset.width, offset.height) < CodyMotion.longPressAllowableMovement {
                    unpinMenuTool = tool
                }
            }
    }

    private func unpinMenuButton(for tool: CodyNovaPinnedTool) -> some View {
        Button(role: .destructive) {
            unpinMenuTool = nil
            unpin(tool)
        } label: {
            Label("Unpin from Tab Bar", systemImage: "pin.slash")
                .padding(CodySpacing.md)
        }
    }

    private func unpin(_ tool: CodyNovaPinnedTool) {
        withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
            if selection == .tool(tool) { select(.home) }
            tabStore.unpin(tool)
        }
    }

    /// Calm frosted Material pill at rest (matches Screenshot 2 & 6).
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
        .frame(minWidth: Self.restingPillMinWidth, maxWidth: Self.restingPillWidth)
        .frame(height: Self.restingPillHeight)
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
        DragGesture(minimumDistance: 10, coordinateSpace: .named("novaTabBarSpace"))
            .onChanged { value in
                let count = items.count
                guard rowWidth > 0, count > 0, pinLift == nil, pinDragState.draggingTool == nil else { return }
                if !isScrubbing {
                    guard abs(value.translation.width) >= 10,
                          abs(value.translation.width) >= abs(value.translation.height) * 0.75 else {
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

private struct PinnedTabEditingMotion: ViewModifier {
    let isEditing: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), isEditing {
            content.phaseAnimator([-2.0, 2.0]) { view, angle in
                view.rotationEffect(.degrees(angle))
            } animation: { _ in .easeInOut(duration: 0.19) }
        } else {
            content
        }
    }
}

/// The cutout and its mark share a single corner frame. The cutout lets the
/// tab surface show through around the mark in both color schemes.
private struct CodyTabActivityMark: ViewModifier {
    let activity: SubAgentActivity?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let markSize: CGFloat = 8
    private let cutoutSize: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .mask(alignment: .topTrailing) {
                Rectangle()
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .frame(width: cutoutSize, height: cutoutSize)
                            .opacity(activity == nil ? 0 : 1)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .overlay(alignment: .topTrailing) {
                if let activity {
                    mark(for: activity)
                        .frame(width: cutoutSize, height: cutoutSize)
                        .transition(.scale(scale: 0.65).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private func mark(for activity: SubAgentActivity) -> some View {
        switch activity {
        case .unread:
            Circle()
                .fill(CodyColors.iconAccent)
                .frame(width: markSize, height: markSize)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: markSize, weight: .bold))
                .foregroundStyle(CodyColors.statusErrorText)
        case .running:
            if reduceMotion {
                Image(systemName: "hourglass")
                    .font(.system(size: markSize, weight: .semibold))
                    .foregroundStyle(CodyColors.iconAccent)
            } else {
                ProgressView()
                    .tint(CodyColors.iconAccent)
                    .scaleEffect(0.5)
            }
        }
    }
}
