import Combine
import SwiftUI
import UIKit

enum CodyNovaTab: String, CaseIterable, Identifiable, Hashable {
    case chat
    case explore
    case files

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .chat: "Chat"
        case .explore: "Explore"
        case .files: "Files"
        }
    }

    var iconName: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .explore: "square.grid.2x2"
        case .files: "folder"
        }
    }

    var selectedIconName: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .explore: "square.grid.2x2.fill"
        case .files: "folder.fill"
        }
    }
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
}

/// Lightweight keyboard visibility observer used by the Nova root shell to
/// smoothly hide the floating bottom tab bar whenever the software keyboard is active.
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
