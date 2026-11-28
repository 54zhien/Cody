import SwiftUI

// MARK: - [T-home-list-lazy-rows] One concrete row per session id

// Why these are named structs and not inline row builders:
//
// A List only builds the rows on screen if it can count rows WITHOUT running
// their content - which it can when every ForEach element is statically one
// view. The home list's elements were `if let session = sessionForRow(id) { … }`
// (zero or one view) and, on iPhone, an `AnyView` (any number of views), so
// every ContentView body pass ran all ~4,700 row closures to count them. Field
// log 2026-10-03 22:08-22:23 (1.15, 4,722 sessions): "one pass resolved 4707 of
// 4707 rows" on every pass, and a 240-420 ms [MainStall] on 24 of 29 pushes into
// a chat and on returning home - the hitch the user saw on every back swipe.
//
// Each struct is exactly one view of a fixed type, so the ForEach row count is
// `ids.count` and only visible rows are built. The struct is also the type
// boundary that f8012dfa4 needed: the parent's type names only the struct, and
// the 8-modifier chain lives in the struct's own body type, so stackList's
// metadata stays shallow without the AnyView that made rows uncountable.
//
// All inputs are values (no closures capturing ContentView - see
// [T-ios-crash-contextmenu-uaf]); the menu goes through the same
// SessionMenuActionChannel as before.

/// iPhone (compact, `stackList`) row: a tap opens the session through
/// `SessionMenuActionChannel` (`.open`), which replaces the navigation path.
///
/// [T-nav-ghost-row-link] This used to be a hidden `NavigationLink(value:)` in
/// the row's background. After a session had been opened from its row and the
/// user swiped back, the next PROGRAMMATIC push (a new chat from the FAB or a
/// folder card) brought that session back underneath the new chat, so Back had
/// to be pressed twice. The mechanism - the List's value link being re-applied
/// to the path - is inferred from the log below (nothing in the app writes that
/// element; no deferred navigation was pending), not reproduced in isolation. Field log
/// 2026-10-04 12:31-12:33: FD704863 entered from its row (no openSession line),
/// swiped back (nav depth=0), then a new chat logged `nav depth=2` with
/// FD704863's view rebuilt under the draft; new chats whose previous entry was a
/// programmatic push stayed at depth 1. With no value links in the list, every
/// push from the home list goes through the app's own path writes.
struct SessionStackRow: View {
    let session: ChatSession
    let isActive: Bool
    let isSuspended: Bool
    let highlightQuery: String?
    let matchSnippet: String?
    let isRegeneratingTitle: Bool
    let inFolder: Bool
    let menuActions: SessionMenuActionChannel
    let dragSessionID: String?
    var isHighlighted: Bool = false

    var body: some View {
        let _ = HomeListPerf.rowBuilt()
        HStack(spacing: 0) {
            menuRow
            if let dragSessionID {
                SessionRowDragHandle(sessionID: dragSessionID)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var menuRow: some View {
        Button { [menuActions, sid = session.id] in
            menuActions.send(.open(sid))
        } label: {
            SessionRow(
                session: session,
                isHighlighted: isHighlighted,
                // [T-ios-ipad-sidebar-running-indicator-stale] Running / suspended as
                // VALUES so a flip re-evaluates this row in place.
                isActive: isActive,
                isSuspended: isSuspended,
                highlightQuery: highlightQuery,
                matchSnippet: matchSnippet,
                isFrameless: true
            )
            // [T-ios-session-list-equatable-jank] Gate parent-driven re-eval on
            // SessionRow's cheap custom ==.
            .equatable()
            .padding(.leading, inFolder ? 18 : 0)
        }
        .buttonStyle(SessionRowPressStyle())
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .overlay {
            if isRegeneratingTitle {
                ProgressView()
                    .padding(.trailing, CodySpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.contextMenuPreview, SessionMenuLiftShape())
        .contextMenu {
            // [T-ios-crash-contextmenu-uaf] Value-only menu view, no closure captures.
            SessionContextMenu(
                key: MenuKey(sid: session.id, pinned: session.isPinned, title: session.title, filed: session.isFiled),
                actions: menuActions
            )
            .equatable()
        } preview: {
            SessionMenuPreview(title: session.title, sessionID: session.id)
        }
    }
}

/// iPad / Mac (`splitList`) row: selected through `List(selection:)` + `.tag`.
struct SessionSplitRow: View {
    let session: ChatSession
    let isHighlighted: Bool
    let isActive: Bool
    let isSuspended: Bool
    let highlightQuery: String?
    let matchSnippet: String?
    let isRegeneratingTitle: Bool
    /// The id the context menu acts on: the real id for a persisted draft row,
    /// nil for a never-sent draft (no menu). See [T-ios-ipad-new-session-contextmenu-broken].
    let menuSid: String?
    let inFolder: Bool
    let isLastInFolder: Bool
    let menuActions: SessionMenuActionChannel

    private static let highlightFill = CodyColors.bgSecondary

    var body: some View {
        let _ = HomeListPerf.rowBuilt()
        HStack(spacing: 0) {
            menuRow
            if let menuSid {
                SessionRowDragHandle(sessionID: menuSid)
            }
        }
        .tag(session.id)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(
            ZStack {
                if inFolder {
                    FolderMemberRowBackground(isLast: isLastInFolder)
                    // Flush selection band inside the group; the last member's
                    // band takes the container's bottom radii.
                    if isHighlighted {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: isLastInFolder ? CodyRadius.surface : 0,
                            bottomTrailingRadius: isLastInFolder ? CodyRadius.surface : 0,
                            topTrailingRadius: 0,
                            style: .circular
                        )
                        .fill(Self.highlightFill)
                        .padding(.horizontal, CodySpacing.xsPlus + CodySpacing.px / 2)
                        .padding(.bottom, isLastInFolder ? CodySpacing.xs + CodySpacing.px / 2 : 0)
                    }
                } else {
                    RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                        .fill(isHighlighted ? Self.highlightFill : Color.clear)
                        .padding(.horizontal, CodySpacing.xsPlus)
                        .padding(.vertical, CodySpacing.xxs)
                }
            }
        )
    }

    private var menuRow: some View {
        SessionRow(
            session: session,
            isHighlighted: isHighlighted,
            isActive: isActive,
            isSuspended: isSuspended,
            highlightQuery: highlightQuery,
            matchSnippet: matchSnippet
        )
        .equatable()
        .overlay {
            if isRegeneratingTitle {
                ZStack {
                    CodyColors.bgCanvas.opacity(0.7)
                    ProgressView()
                }
            }
        }
        // [T-ios-selected-session-contextmenu] On the row CONTENT, below the
        // selection layer, so it fires on the selected row too (GH#30).
        .contentShape(.contextMenuPreview, SessionMenuLiftShape())
        .contextMenu {
            if let menuSid {
                SessionContextMenu(
                    key: MenuKey(sid: menuSid, pinned: session.isPinned, title: session.title, filed: session.isFiled),
                    actions: menuActions
                )
                .equatable()
            }
        } preview: {
            if menuSid != nil {
                SessionMenuPreview(title: session.title, sessionID: session.id)
            }
        }
    }
}

extension ChatSession {
    /// Stand-in for a row id that resolves to no session. Group ids come from
    /// `sessions` (plus the iPad draft, which sessionForRow resolves), so this
    /// should never render; it exists so a row is always exactly one view.
    /// HomeListPerf counts these as `nil` lookups.
    static func missingRowPlaceholder(_ id: String) -> ChatSession {
        ChatSession(id: id, title: nil, category: nil, modelId: "",
                    createdAt: .distantPast, updatedAt: .distantPast, lastMessage: nil)
    }
}

/// [T-nav-ghost-row-link] Press feedback for SessionStackRow's Button: the whole
/// row is the hit area and dims while pressed, standing in for the cell
/// highlight the hidden NavigationLink used to get. A custom style also keeps
/// List from tinting the row's text with the accent colour.
struct SessionRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: CodyRadius.control)
                        .fill(CodyColors.bgSecondary)
                        .padding(.horizontal, CodySpacing.xsPlus)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Limits the snapshot lifted from the row during the native menu transition.
struct SessionMenuLiftShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bounds = CGRect(
            x: rect.minX, y: rect.minY + 4,
            width: min(rect.width, 248), height: max(0, rect.height - 8)
        )
        return RoundedRectangle(cornerRadius: 12).path(in: bounds)
    }
}

/// The settled menu shows its own opaque title instead of a snapshot of the list.
struct SessionMenuPreview: View {
    let title: String?
    let sessionID: String?
    @ObservedObject private var locks = SessionLockStore.shared

    private var label: String {
        if let sessionID, locks.isVisuallyLocked(sessionID) {
            return AppLocalized("Locked")
        }
        return title ?? AppLocalized("New Chat")
    }

    var body: some View {
        Text(verbatim: label)
            .font(.headline)
            .foregroundStyle(CodyColors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 248)
            .fixedSize(horizontal: true, vertical: true)
            .background(CodyColors.bgPrimary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SessionRowDragHandle: View {
    let sessionID: String

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(CodyColors.textTertiary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .draggable(sessionID)
            .accessibilityLabel("Move to Group")
    }
}
