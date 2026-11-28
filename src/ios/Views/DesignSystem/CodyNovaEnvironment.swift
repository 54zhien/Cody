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

    init() {
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

    func pin(_ tool: CodyNovaPinnedTool) {
        guard !pinnedTools.contains(tool) else { return }
        if pinnedTools.count >= Self.maxPinnedCount {
            pinnedTools.removeLast()
        }
        pinnedTools.append(tool)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
    @Published var draggingTool: CodyNovaPinnedTool? = nil
    @Published var dragLocation: CGPoint = .zero
    /// Stored non-@Published so layout passes of the tab bar never trigger parent ContentView re-renders.
    var tabBarFrame: CGRect = .zero

    var isHoveringTabBar: Bool {
        guard draggingTool != nil, !tabBarFrame.isEmpty else { return false }
        return tabBarFrame.insetBy(dx: -16, dy: -44).contains(dragLocation)
    }

    func begin(tool: CodyNovaPinnedTool, at location: CGPoint) {
        draggingTool = tool
        dragLocation = location
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func update(location: CGPoint) {
        let wasHovering = isHoveringTabBar
        dragLocation = location
        if isHoveringTabBar && !wasHovering {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func end(pinInto store: CodyNovaTabStore) {
        if let tool = draggingTool, isHoveringTabBar {
            store.pin(tool)
        }
        draggingTool = nil
    }

    func cancel() {
        draggingTool = nil
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
        // Runtime hardware radius lookup with safe fallback to standard Face ID / flat screen radii.
        let radiusKey = ["_", "display", "Corner", "Radius"].joined()
        if let value = screen.value(forKey: radiusKey) as? CGFloat, value > 0 {
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
                        .frame(width: CodySpacing.sm, height: CodySpacing.sm)
                        .overlay {
                            Circle()
                                .stroke(CodyColors.bgCanvas, lineWidth: 1.5)
                        }
                        .offset(x: 3, y: -3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
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
