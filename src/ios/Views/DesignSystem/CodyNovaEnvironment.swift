import Combine
import SwiftUI
import UIKit

/// Tools that can be browsed on the Explore ("More") screen and long-press pinned
/// directly onto the customizable Nova bottom icon bar.
enum CodyNovaPinnedTool: String, CaseIterable, Identifiable, Hashable, Codable {
    case files
    case terminal
    case skills
    case mcp
    case browser
    case agentTools
    case subAgents
    case soul
    case memory
    case providers
    case usage
    case alarms

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .files: "Files"
        case .terminal: "Terminal"
        case .skills: "Skills"
        case .mcp: "MCP"
        case .browser: "Browser"
        case .agentTools: "Agent Tools"
        case .subAgents: "Sub Agents"
        case .soul: "Soul"
        case .memory: "Memory"
        case .providers: "Providers"
        case .usage: "Usage"
        case .alarms: "Alarms"
        }
    }

    var iconName: String {
        switch self {
        case .files: "folder"
        case .terminal: "terminal"
        case .skills: "puzzlepiece.extension"
        case .mcp: "square.stack.3d.up"
        case .browser: "safari"
        case .agentTools: "wrench.and.screwdriver"
        case .subAgents: "sparkles.rectangle.stack"
        case .soul: "sparkles"
        case .memory: "brain.head.profile"
        case .providers: "cpu"
        case .usage: "chart.line.uptrend.xyaxis"
        case .alarms: "alarm"
        }
    }

    var selectedIconName: String {
        switch self {
        case .files: "folder.fill"
        case .terminal: "terminal.fill"
        case .skills: "puzzlepiece.extension.fill"
        case .mcp: "square.stack.3d.up.fill"
        case .browser: "safari.fill"
        case .agentTools: "wrench.and.screwdriver.fill"
        case .subAgents: "sparkles.rectangle.stack.fill"
        case .soul: "sparkles"
        case .memory: "brain.head.profile.fill"
        case .providers: "cpu.fill"
        case .usage: "chart.line.uptrend.xyaxis"
        case .alarms: "alarm.fill"
        }
    }

    var tint: CodyCategoryTint {
        switch self {
        case .files: .blue
        case .terminal: .green
        case .skills: .blue
        case .mcp: .green
        case .browser: .blue
        case .agentTools: .purple
        case .subAgents: .purple
        case .soul: .purple
        case .memory: .purple
        case .providers: .blue
        case .usage: .green
        case .alarms: .orange
        }
    }

    /// Multicolor layered vector icon rendered on Explore cards.
    var exploreColorIcon: CodyExploreIcon {
        switch self {
        case .files: .files
        case .terminal: .terminal
        case .skills: .skills
        case .mcp: .mcp
        case .browser: .browser
        case .agentTools: .agentTools
        case .subAgents: .subAgents
        case .soul: .soul
        case .memory: .memory
        case .providers: .providers
        case .usage: .usage
        case .alarms: .alarms
        }
    }

    /// Vivid accent color for Explore tile badges and pinned indicators.
    var exploreGlyphColor: Color {
        switch self {
        case .files: Color(red: 0.25, green: 0.65, blue: 0.98)
        case .terminal: Color(red: 0.20, green: 0.45, blue: 0.95)
        case .skills: Color(red: 0.28, green: 0.78, blue: 0.72)
        case .mcp: Color(red: 0.35, green: 0.74, blue: 0.42)
        case .browser: Color(red: 0.22, green: 0.62, blue: 0.96)
        case .agentTools: Color(red: 0.56, green: 0.36, blue: 0.92)
        case .subAgents: Color(red: 0.48, green: 0.32, blue: 0.90)
        case .soul: Color(red: 0.94, green: 0.74, blue: 0.22)
        case .memory: Color(red: 0.60, green: 0.38, blue: 0.90)
        case .providers: Color(red: 0.24, green: 0.56, blue: 0.96)
        case .usage: Color(red: 0.52, green: 0.80, blue: 0.24)
        case .alarms: Color(red: 0.52, green: 0.30, blue: 0.86)
        }
    }
}

/// Active destination in the Nova root shell: fixed Home (Chat), user-pinned custom tools, or fixed More (Explore).
enum CodyNovaDestination: Hashable, Identifiable {
    case home
    case tool(CodyNovaPinnedTool)
    case more

    var id: String {
        switch self {
        case .home: "home"
        case .tool(let t): "tool.\(t.rawValue)"
        case .more: "more"
        }
    }
}

/// Legacy tab alias kept for source compatibility where needed.
enum CodyNovaTab: String, CaseIterable, Identifiable, Hashable {
    case chat
    case explore
    case files

    var id: String { rawValue }
}

/// Persistent store for the user's customizable Nova bottom-bar pinned tools.
/// Supports long-press pin/unpin from the Explore ("More") grid (up to 4 custom icons between Home and More).
@MainActor
final class CodyNovaTabStore: ObservableObject {
    static let maxPinnedCount = 4
    private static let storageKey = "cody.nova.pinnedBottomTools.v1"
    private static let defaultPinned: [CodyNovaPinnedTool] = [.skills, .terminal, .files]

    @Published var pinnedTools: [CodyNovaPinnedTool] {
        didSet { persist() }
    }

    @Published private(set) var exploreOrder = CodyNovaPinnedTool.allCases {
        didSet { UserDefaults.standard.set(exploreOrder.map(\.rawValue), forKey: Self.exploreOrderKey) }
    }
    private static let exploreOrderKey = "cody.nova.exploreOrder.v1"

    init() {
        if let order = UserDefaults.standard.stringArray(forKey: Self.exploreOrderKey) {
            var stored = Set<CodyNovaPinnedTool>()
            let saved = order.compactMap(CodyNovaPinnedTool.init(rawValue:)).filter { stored.insert($0).inserted }
            exploreOrder = saved + CodyNovaPinnedTool.allCases.filter { !stored.contains($0) }
        }
        if let raw = UserDefaults.standard.stringArray(forKey: Self.storageKey) {
            let decoded = raw.compactMap(CodyNovaPinnedTool.init(rawValue:))
            self.pinnedTools = Array(decoded.prefix(Self.maxPinnedCount))
        } else {
            self.pinnedTools = Self.defaultPinned
        }
    }

    func isPinned(_ tool: CodyNovaPinnedTool) -> Bool {
        pinnedTools.contains(tool)
    }

    func pin(_ tool: CodyNovaPinnedTool, at index: Int? = nil) {
        let alreadyPinned = pinnedTools.contains(tool)
        guard !alreadyPinned || index != nil else { return }
        // Keep existing shortcuts when the bar is full. The user can remove
        // one explicitly before adding another.
        guard alreadyPinned || pinnedTools.count < Self.maxPinnedCount else { return }
        var updated = pinnedTools.filter { $0 != tool }
        updated.insert(tool, at: min(max(0, index ?? updated.count), updated.count))
        guard updated != pinnedTools else { return }
        pinnedTools = updated
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func saveExploreOrder(_ order: [CodyNovaPinnedTool]) {
        if order != exploreOrder { exploreOrder = order }
    }

    func unpin(_ tool: CodyNovaPinnedTool) {
        guard let idx = pinnedTools.firstIndex(of: tool) else { return }
        pinnedTools.remove(at: idx)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func togglePin(_ tool: CodyNovaPinnedTool) {
        if isPinned(tool) {
            unpin(tool)
        } else {
            pin(tool)
        }
    }

    private func persist() {
        UserDefaults.standard.set(pinnedTools.map(\.rawValue), forKey: Self.storageKey)
    }
}

/// Coordinates long-press drag-and-drop pinning from Explore cards directly onto the bottom Nova tab bar.
@MainActor
final class CodyNovaPinDragState: ObservableObject {
    @Published private(set) var draggingTool: CodyNovaPinnedTool?
    @Published private(set) var dragLocation: CGPoint = .zero
    @Published private(set) var hasLiftedCard = false
    @Published private(set) var previewOrder: [CodyNovaPinnedTool]?
    @Published private(set) var insertionIndex: Int?
    @Published private(set) var landingFrame: CGRect?
    @Published private(set) var isLandingOnBar = false
    var tabBarFrame: CGRect = .zero
    var tabFrames: [CodyNovaDestination: CGRect] = [:]
    var previewFrame: CGRect = .zero
    var cardFrames: [CodyNovaPinnedTool: CGRect] = [:]
    private var sourceFrame: CGRect = .zero
    private var initialTouch: CGPoint = .zero

    var previewLocation: CGPoint {
        guard !isHoveringTabBar, !sourceFrame.isEmpty else { return dragLocation }
        return CGPoint(x: sourceFrame.midX + dragLocation.x - initialTouch.x,
                       y: sourceFrame.midY + dragLocation.y - initialTouch.y)
    }
    private let crossingFeedback = UIImpactFeedbackGenerator(style: .light)

    var isHoveringTabBar: Bool { insertionIndex != nil }

    func begin(tool: CodyNovaPinnedTool, at location: CGPoint, frame: CGRect, order: [CodyNovaPinnedTool]) {
        guard draggingTool == nil else { return }
        sourceFrame = cardFrames[tool] ?? frame
        initialTouch = location
        dragLocation = location
        previewOrder = order
        draggingTool = tool
        crossingFeedback.prepare()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func update(location: CGPoint, pinned: [CodyNovaPinnedTool], reduceMotion: Bool, allowsReordering: Bool) {
        guard let tool = draggingTool, landingFrame == nil else { return }
        if !hasLiftedCard {
            let travel = hypot(location.x - initialTouch.x, location.y - initialTouch.y)
            guard travel >= 6 else { return }
            withAnimation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion)) {
                hasLiftedCard = true
            }
        }
        dragLocation = location
        let fits = pinned.contains(tool) || pinned.count < CodyNovaTabStore.maxPinnedCount
        let hitsBar = fits && !tabBarFrame.isEmpty && tabBarFrame.insetBy(dx: -12, dy: -18).contains(location)
        let isRTL = (tabFrames[.home]?.midX ?? 0) > (tabFrames[.more]?.midX ?? 0)
        let newIndex = hitsBar ? pinned.filter { member in
            guard member != tool, let frame = tabFrames[.tool(member)] else { return false }
            return isRTL ? frame.midX > location.x : frame.midX < location.x
        }.count : nil
        if newIndex != insertionIndex {
            if insertionIndex == nil && newIndex != nil { crossingFeedback.impactOccurred() }
            withAnimation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion)) {
                insertionIndex = newIndex
            }
        }
        guard newIndex == nil, allowsReordering, var order = previewOrder,
              let target = order.first(where: { $0 != tool && cardFrames[$0]?.contains(location) == true }),
              let from = order.firstIndex(of: tool), let to = order.firstIndex(of: target),
              let frame = cardFrames[target],
              frame.insetBy(dx: frame.width * 0.18, dy: frame.height * 0.18).contains(location)
        else { return }
        order.remove(at: from)
        order.insert(tool, at: to)
        withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { previewOrder = order }
    }

    func end(at location: CGPoint, in store: CodyNovaTabStore, reduceMotion: Bool, allowsReordering: Bool) {
        guard let tool = draggingTool, landingFrame == nil else { return }
        update(location: location, pinned: store.pinnedTools, reduceMotion: reduceMotion, allowsReordering: allowsReordering)
        guard hasLiftedCard else { reset(); return }
        if let insertionIndex {
            let target = previewFrame.isEmpty ? (tabFrames[.more] ?? tabBarFrame) : previewFrame
            store.pin(tool, at: insertionIndex)
            settle(at: target, intoBar: true, reduceMotion: reduceMotion)
        } else if allowsReordering, let order = previewOrder, order != store.exploreOrder,
                  cardFrames.values.contains(where: { $0.contains(location) }) {
            store.saveExploreOrder(order)
            settle(at: cardFrames[tool] ?? sourceFrame, intoBar: false, reduceMotion: reduceMotion)
        } else {
            cancel(reduceMotion: reduceMotion)
        }
    }

    func cancel(reduceMotion: Bool) {
        guard draggingTool != nil, landingFrame == nil else { return }
        guard hasLiftedCard else { reset(); return }
        settle(at: sourceFrame, intoBar: false, reduceMotion: reduceMotion)
    }

    private func settle(at frame: CGRect, intoBar: Bool, reduceMotion: Bool) {
        guard #available(iOS 17.0, *), !reduceMotion, !frame.isEmpty else {
            reset()
            return
        }
        withAnimation(CodyMotion.house, completionCriteria: .logicallyComplete) {
            isLandingOnBar = intoBar
            if !intoBar { insertionIndex = nil }
            landingFrame = frame
        } completion: {
            guard self.landingFrame != nil else { return }
            self.reset()
        }
    }

    func reset() {
        draggingTool = nil
        hasLiftedCard = false
        landingFrame = nil
        isLandingOnBar = false
        insertionIndex = nil
        previewOrder = nil
        previewFrame = .zero
    }
}

/// Hardware display corner geometry helper used to align bottom Liquid Glass capsules
/// concentrically with the physical iPhone display corners.
@MainActor
enum CodyDisplayGeometry {
    /// Active screen's physical display corner radius in points (e.g. ~55pt on iPhone Pro,
    /// ~47pt on standard Face ID iPhones, 0pt on Home-button devices).
    static var displayCornerRadius: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let screen = activeScene?.screen ?? UIScreen.main
        // Runtime hardware radius lookup with selector check and safe fallback.
        let radiusKey = ["_", "display", "Corner", "Radius"].joined()
        if screen.responds(to: NSSelectorFromString(radiusKey)),
           let value = screen.value(forKey: radiusKey) as? CGFloat, value > 0 {
            return value
        }
        let bottomSafe = activeScene?.keyWindow?.safeAreaInsets.bottom ?? 0
        return bottomSafe >= 30 ? 55 : 0
    }

    /// Physical screen-edge inset (horizontal and bottom) that places a capsule of height `capsuleHeight`
    /// so its corner circle center coincides with the physical display corner center (`R_screen - H/2`).
    static func concentricEdgeInset(forCapsuleHeight capsuleHeight: CGFloat) -> CGFloat {
        let screenRadius = displayCornerRadius
        let capsuleRadius = capsuleHeight / 2
        guard screenRadius > capsuleRadius else {
            return 16
        }
        return max(12, screenRadius - capsuleRadius)
    }

    /// Current active window's bottom safe area inset (0 on Home-button devices, ~34pt on Face ID iPhones).
    static var bottomSafeAreaInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = activeScene?.windows.first(where: \.isKeyWindow) ?? activeScene?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }
}

/// Iconic two-bar unequal sidebar drawer glyph backed by our self-drawn vector SVG asset,
/// with an optional 8×8pt unread badge dot (matching `SideMenuBadgedIcon`).
struct CodyDrawerGlyph: View {
    var color: Color = CodyColors.iconPrimary
    var size: CGFloat = 24
    var showsUnreadBadge: Bool = true
    @Environment(\.novaSidebarHasUnread) private var hasUnread

    var body: some View {
        CodyIconView(.drawer, size: size)
            .foregroundStyle(color)
            .overlay(alignment: .topTrailing) {
                if showsUnreadBadge && hasUnread {
                    Circle()
                        .fill(CodyColors.statusErrorText)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
    }
}

struct CodyDrawerAccessibility: ViewModifier {
    @Environment(\.novaSidebarHasUnread) private var hasUnread

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(Text("Open sidebar"))
            .accessibilityValue(hasUnread ? Text("Unread messages") : Text(""))
    }
}

private struct NovaSidebarHasUnreadKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct OpenNovaDrawerKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct NovaNewChatActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct NovaTabBarBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct NovaHostedChatKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var openNovaDrawer: (() -> Void)? {
        get { self[OpenNovaDrawerKey.self] }
        set { self[OpenNovaDrawerKey.self] = newValue }
    }

    var novaNewChatAction: (() -> Void)? {
        get { self[NovaNewChatActionKey.self] }
        set { self[NovaNewChatActionKey.self] = newValue }
    }

    var novaTabBarBottomInset: CGFloat {
        get { self[NovaTabBarBottomInsetKey.self] }
        set { self[NovaTabBarBottomInsetKey.self] = newValue }
    }

    var isNovaHostedChat: Bool {
        get { self[NovaHostedChatKey.self] }
        set { self[NovaHostedChatKey.self] = newValue }
    }

    var novaSidebarHasUnread: Bool {
        get { self[NovaSidebarHasUnreadKey.self] }
        set { self[NovaSidebarHasUnreadKey.self] = newValue }
    }
}

/// Lightweight keyboard visibility observer used by the Nova root shell to
/// smoothly hide the bottom icon bar whenever the software keyboard is active.
@MainActor
final class CodyKeyboardObserver: ObservableObject {
    @Published private(set) var isVisible: Bool = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in
                self?.isVisible = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.isVisible = false
            }
            .store(in: &cancellables)
    }
}
