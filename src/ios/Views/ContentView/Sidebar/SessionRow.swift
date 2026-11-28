//
//  SessionRow.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  Session list rows and their parts: the category icon map, folder composed
//  icon, SessionRow, FolderSummaryLine, the Face ID lock effect,
//  RemoteSessionRow and the suspended ring.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Session Row

/// Shared symbol and muted tint for session rows and folder summaries.
func sessionCategoryIcon(for category: String?) -> (systemName: String, color: Color) {
    let icon = sessionCategoryBadge(for: category)
    return (icon.systemName, icon.tint.color)
}

private func sessionCategoryBadge(for category: String?) -> (systemName: String, tint: CodyCategoryTint) {
    switch category {
    case "code":         return ("terminal.fill", .orange)
    case "writing":      return ("doc.text.fill", .blue)
    case "research":     return ("globe.americas.fill", .green)
    case "analysis":     return ("chart.pie.fill", .purple)
    case "creative":     return ("paintbrush.pointed.fill", .red)
    case "chat":         return ("bubble.left.fill", .green)
    case "math":         return ("number.circle.fill", .purple)
    case "translation":  return ("character.bubble", .blue)
    case "health":       return ("heart.fill", .red)
    case "finance":      return ("banknote.fill", .green)
    case "travel":       return ("map.fill", .orange)
    case "education":    return ("book.closed.fill", .blue)
    case "design":       return ("paintpalette.fill", .red)
    case "productivity": return ("calendar.badge.checkmark", .orange)
    case "support":      return ("gearshape.fill", .orange)
    case "other":        return ("square.grid.2x2.fill", .neutral)
    default:             return ("bubble.left.fill", .neutral)
    }
}

/// The "grouped list" glyph from the user-provided asset: two rounded
/// square outlines on the left, four list lines on the right. Traced from
/// the 1024-unit SVG; squares are drawn as even-odd rings so the whole
/// glyph is a single fill (no stroke-vs-fill mixing).
struct GroupGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let u = rect.width / 1024.0

        func ring(x: CGFloat, y: CGFloat) {
            // Outer 325.8×325.8 with r 93; inner inset by the 46.5 stroke.
            let outer = CGRect(x: x * u, y: y * u, width: 325.8 * u, height: 325.8 * u)
            let inner = outer.insetBy(dx: 46.5 * u, dy: 46.5 * u)
            p.addRoundedRect(in: outer, cornerSize: CGSize(width: 93 * u, height: 93 * u), style: .continuous)
            p.addRoundedRect(in: inner, cornerSize: CGSize(width: 46.5 * u, height: 46.5 * u), style: .continuous)
        }
        func line(cy: CGFloat) {
            let r = CGRect(x: 558.5 * u, y: (cy - 23.27) * u, width: 325.8 * u, height: 46.5 * u)
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 23.27 * u, height: 23.27 * u))
        }

        ring(x: 139.6, y: 139.6)
        ring(x: 139.6, y: 511.9)
        line(cy: 209.5)
        line(cy: 395.6)
        line(cy: 581.8)
        line(cy: 768.0)
        return p
    }
}

/// Group badge tinted by its newest member's category.
struct FolderComposedIcon: View {
    let glyphs: [FolderGlyph]
    var diameter: CGFloat = CodyMetrics.Sidebar.iconSize

    var body: some View {
        let tint = glyphs.first?.color ?? CodyCategoryTint.neutral.color
        let shape = RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
        GroupGlyphShape()
            .fill(tint, style: FillStyle(eoFill: true))
            .frame(width: diameter * 0.64, height: diameter * 0.64)
            .frame(width: diameter, height: diameter)
            .background(shape.fill(tint.opacity(0.08)))
            .background(shape.fill(CodyColors.bgListIcon))
            .overlay {
                shape.strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }
}

struct SessionRow: View, Equatable {
    // [T-ios-session-list-equatable-jank] Custom Equatable so `.equatable()` at
    // the call site gates parent-driven re-evaluation on a CHEAP compare of just
    // the fields this row actually renders — instead of SwiftUI deep-comparing
    // the whole `ChatSession` value (the `let session` input). Post the
    // sessionsByIdCache fix, the HangDetector scroll stack still showed
    // AGGraphSetOutputValue → ChatSession.== recursion: it was THIS row's
    // whole-struct input being compared per transaction × visible rows.
    // Comparing only the rendered fields (all short) collapses that to a handful
    // of cheap, short-circuiting comparisons. The @ObservedObject trackers below
    // still drive in-place re-eval on running/lock/font changes (Equatable only
    // gates the parent-push path, not observed-object invalidation).
    static func == (lhs: SessionRow, rhs: SessionRow) -> Bool {
        lhs.session.id == rhs.session.id
            && lhs.session.title == rhs.session.title
            && lhs.session.lastMessage == rhs.session.lastMessage
            && lhs.session.updatedAt == rhs.session.updatedAt
            && lhs.session.pinnedAt == rhs.session.pinnedAt
            && lhs.session.category == rhs.session.category
            && lhs.session.source == rhs.session.source
            && lhs.session.remoteDeviceId == rhs.session.remoteDeviceId
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.highlightQuery == rhs.highlightQuery
            && lhs.matchSnippet == rhs.matchSnippet
            && lhs.isActiveOverride == rhs.isActiveOverride
            && lhs.isSuspendedOverride == rhs.isSuspendedOverride
            && lhs.isFrameless == rhs.isFrameless
    }

    let session: ChatSession
    var isHighlighted: Bool = false
    var highlightQuery: String? = nil
    /// When set, replaces the generic `lastMessage` preview in the subtitle
    /// slot with this body-extracted snippet (~100 chars around the first
    /// hit). Only populated when the search hit was on message body —
    /// title matches keep the highlighted title in the title slot and fall
    /// back to `lastMessage` below. (T-search-highlight 8edb74f2)
    var matchSnippet: String? = nil
    /// Running / suspended state passed in as VALUES by the sidebar list so a
    /// flip changes this view's value and re-evaluates `body` in place (same
    /// ForEach identity — no cell rebuild / scroll jump). When nil (e.g. the
    /// bare `SessionRow(session:)` call site) we fall back to reading the
    /// observed trackers directly. [T-ios-ipad-sidebar-running-indicator-stale]
    var isActiveOverride: Bool? = nil
    var isSuspendedOverride: Bool? = nil
    let isFrameless: Bool
    @ObservedObject private var activityTracker = SessionActivityTracker.shared
    @ObservedObject private var concurrencyManager = SessionConcurrencyManager.shared
    @ObservedObject private var lockStore = SessionLockStore.shared
    // [T-ios-session-paused-badge] Observe the badge-state queue so a session's
    // "!" paused badge appears/clears in place (same row identity) when the
    // queue changes. The custom Equatable above gates only the parent-push
    // path; @ObservedObject still drives in-place re-eval on store changes.
    @ObservedObject private var badgeStore = SessionBadgeStore.shared
    // Observe App Base font scale so the row re-evaluates when the user moves
    // the slider. The row's fonts use hardcoded `.system(size:)` which ignore
    // Dynamic Type, so we must explicitly multiply by the App Base scale.
    @ObservedObject private var fontSettings = FontSettings.shared

    init(session: ChatSession,
         isHighlighted: Bool = false,
         isActive: Bool? = nil,
         isSuspended: Bool? = nil,
         highlightQuery: String? = nil,
         matchSnippet: String? = nil,
         isFrameless: Bool = false) {
        self.session = session
        self.isHighlighted = isHighlighted
        self.isActiveOverride = isActive
        self.isSuspendedOverride = isSuspended
        self.highlightQuery = highlightQuery
        self.matchSnippet = matchSnippet
        self.isFrameless = isFrameless
    }

    private var isActive: Bool {
        isActiveOverride ?? activityTracker.isActive(session.id)
    }

    private var isSuspended: Bool {
        isSuspendedOverride ?? concurrencyManager.isSuspended(session.id)
    }

    /// True when the row should render the lock affordance — global
    /// toggle on, biometric supported, this session is in the locked set,
    /// AND the user hasn't unlocked it in the current run. Without the
    /// `isCurrentlyUnlocked` check, an already-unlocked session keeps
    /// rendering its title + last-message line blurred even though the
    /// detail view is freely accessible — the row blur outlived its
    /// purpose for the rest of the session.
    private var isVisuallyLocked: Bool {
        lockStore.isVisuallyLocked(session.id)
    }

    /// The transient badge to render for this row, after suppressing states that
    /// contradict the row's live activity.
    ///
    /// [T-ios-session-running-shows-pause-badge] A session that is actively
    /// running its agent loop (`isActive`, drawn with the SpinningRing) is by
    /// definition NOT paused — yet a transient `canResume=true` flip mid-run
    /// (interrupted-tail detection at load, a Stop case that then resumes, a
    /// background-suspend that's already back in-flight) can leave a stale
    /// `.paused` in the queue. The launch/foreground reconcile already excludes
    /// active sessions; do the same continuously at render so a spinning row can
    /// never also show ⏸. Non-`.paused` queue states are unaffected.
    private var visibleBadge: SessionBadgeState? {
        guard let badge = badgeStore.topCornerBadge(for: session.id) else { return nil }
        if badge == .paused && isActive { return nil }
        return badge
    }

    /// [T-ios-session-unread-badge] Unread is independent of the status badge,
    /// so a paused session can also show its unread dot.
    private var showsUnreadDot: Bool {
        guard !isHighlighted else { return false }
        return badgeStore.hasUnread(for: session.id)
    }

    var body: some View {
        if isFrameless {
            framelessRow
        } else {
            detailedRow
        }
    }

    private var framelessRow: some View {
        HStack(spacing: CodySpacing.sm) {
            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                highlightedText(
                    session.title ?? AppLocalized("New Chat"),
                    font: .system(size: fontSettings.scaledApp(19), weight: isHighlighted ? .medium : .regular),
                    color: CodyColors.textPrimary
                )
                .lineLimit(1)

                if let snippet = matchSnippet, !snippet.isEmpty {
                    highlightedText(
                        snippet,
                        font: .system(size: fontSettings.scaledApp(14)),
                        color: CodyColors.textSecondary
                    )
                    .lineLimit(2)
                }
            }
            .modifier(LockedRowEffect(isLocked: isVisuallyLocked))
            .frame(maxWidth: .infinity, alignment: .leading)

            statusIndicators(tint: sessionCategoryBadge(for: session.category).tint.color)
        }
        .padding(.trailing, CodySpacing.sm)
        .padding(.vertical, CodySpacing.xs)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isVisuallyLocked ? Text("Locked") : Text(verbatim: session.title ?? AppLocalized("New Chat")))
        .accessibilityValue(Text(verbatim: accessibilityDetails(date: relativeDate(session.updatedAt))))
    }

    @ViewBuilder
    private var detailedRow: some View {
        let icon = sessionCategoryBadge(for: session.category)
        let date = relativeDate(session.updatedAt)
        HStack(spacing: CodyMetrics.Sidebar.itemSpacing) {
            CodyListIconBadge(systemImage: icon.systemName, tint: icon.tint)

            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                HStack(spacing: CodyMetrics.Sidebar.pinnedIconSpacing) {
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(CodyColors.textTertiary)
                            .accessibilityHidden(true)
                    }
                    highlightedText(
                        session.title ?? "New Chat",
                        font: .system(size: fontSettings.scaledApp(16), weight: .semibold),
                        color: CodyColors.textPrimary
                    )
                    .lineLimit(1)
                }

                if let snippet = matchSnippet, !snippet.isEmpty {
                    highlightedText(
                        snippet,
                        font: .system(size: fontSettings.scaledApp(14)),
                        color: CodyColors.textSecondary
                    )
                    .lineLimit(2)
                } else {
                    highlightedText(
                        session.lastMessage ?? "No messages yet",
                        font: .system(size: fontSettings.scaledApp(14)),
                        color: CodyColors.textSecondary
                    )
                    .lineLimit(1)
                }
            }
            // Blur the locked content. Compared to the earlier hard
            // `.clipped()` rectangle, the rounded-rectangle clip + a
            // gentler radius + a soft horizontal fade at the trailing
            // edge let the obfuscated text dissolve into the row
            // background instead of presenting a crisp blurred block.
            //
            // [T-ios16-title-color] The modifier chain (blur+clipShape+mask)
            // is only applied while the session is actually locked. iOS 16's
            // SwiftUI renderer drains color saturation through a stack of
            // even-no-op effect modifiers (mask{Rectangle()} included), which
            // showed up as the session title rendering pale grey on iOS 16
            // while iOS 17+ kept it crisp black. Gating the whole effect
            // chain on the lock flag is the cheapest universal fix.
            .modifier(LockedRowEffect(isLocked: isVisuallyLocked))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(date)
                .font(.system(size: fontSettings.scaledApp(13)))
                .foregroundStyle(CodyColors.textTertiary)
                .lineLimit(1)

            statusIndicators(tint: icon.tint.color)
        }
        .padding(.horizontal, CodyMetrics.Sidebar.rowPaddingH)
        .padding(.vertical, CodySpacing.xxs)
        .frame(minHeight: CodyMetrics.Sidebar.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isVisuallyLocked ? Text("Locked") : Text(verbatim: session.title ?? AppLocalized("New Chat"))
        )
        .accessibilityValue(Text(verbatim: accessibilityDetails(date: date)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        #if DEBUG
        // TEMPORARY height probe — confirms List self-sizing jitter source.
        // PreferenceKey fires on every real layout (incl. the self-size
        // correction), unlike onAppear which fires once pre-layout.
        .background(GeometryReader { g in
            Color.clear.preference(key: RowHeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(RowHeightKey.self) { h in
            probeRowHeight(h, matchSnippet == nil ? "plain" : "snippet")
        }
        #endif
    }

    @ViewBuilder
    private func statusIndicators(tint: Color) -> some View {
        if isActive || isSuspended || isVisuallyLocked || visibleBadge != nil
            || session.source == "shortcut" || session.isRemote || showsUnreadDot {
            VStack(spacing: CodySpacing.xxs) {
                if isSuspended || isActive {
                    SidebarRowActivity(isSuspended: isSuspended, tint: tint)
                }
                if isVisuallyLocked {
                    SidebarRowBadge(systemImage: "lock.fill", tint: CodyColors.textSecondary)
                } else if let badge = visibleBadge {
                    badgeView(for: badge)
                } else if session.source == "shortcut" {
                    SidebarRowBadge(systemImage: "bolt.fill", tint: CodyColors.statusWarningText)
                } else if session.isRemote {
                    SidebarRowBadge(systemImage: "icloud.fill", tint: CodyCategoryTint.blue.color)
                }
                if showsUnreadDot {
                    SidebarUnreadDot()
                }
            }
            .frame(width: CodyMetrics.Sidebar.statusIndicatorSlot)
            .padding(.trailing, isFrameless ? 0 : CodyMetrics.Sidebar.badgeTrailingPadding)
            .accessibilityHidden(true)
        }
    }

    private func accessibilityDetails(date: String) -> String {
        var details: [String] = []
        if session.isPinned { details.append(AppLocalized("Pinned")) }
        if showsUnreadDot { details.append(AppLocalized("Unread")) }
        if isSuspended {
            details.append(AppLocalized("Paused"))
        } else if isActive {
            details.append(AppLocalized("Running"))
        } else if visibleBadge == .paused {
            details.append(AppLocalized("Paused"))
        }
        if !isVisuallyLocked, let preview = matchSnippet ?? session.lastMessage {
            details.append(preview)
        }
        details.append(date)
        return details.joined(separator: ", ")
    }

    @ViewBuilder
    private func badgeView(for state: SessionBadgeState) -> some View {
        switch state {
        case .paused:
            SidebarRowBadge(systemImage: "pause.fill", tint: CodyColors.statusWarningText)
        case .iCloudSyncing:
            SidebarRowBadge(systemImage: "icloud.fill", tint: CodyCategoryTint.blue.color)
        case .unread:
            EmptyView()
        }
    }

    @ViewBuilder
    private func highlightedText(_ text: String, font: Font, color: Color) -> some View {
        if let query = highlightQuery, !query.isEmpty,
           SearchKeywords.firstHit(in: text, terms: SearchKeywords.terms(query)) != nil {
            Text(Self.highlightedAttributedString(text: text, query: query, baseColor: color))
                .font(font)
        } else {
            Text(text).font(font).foregroundStyle(color)
        }
    }

    /// Build a SwiftUI `AttributedString` with `backgroundColor` painted on
    /// every case-insensitive occurrence of every keyword of `query`
    /// ([T-search-multi-keyword]: whitespace separates keywords, and a line
    /// holding several has all of them marked). Matches Android
    /// `highlightedAnnotatedString` (commit 545d585) — same theme-aware
    /// tint, same case-insensitive match, same span-style approach.
    /// (T-search-highlight 8edb74f2)
    static func highlightedAttributedString(text: String, query: String, baseColor: Color) -> AttributedString {
        PerfTrace.measure("SessionRow.highlightedAttributedString") {
            highlightedAttributedStringImpl(text: text, query: query, baseColor: baseColor)
        }
    }

    private static func highlightedAttributedStringImpl(text: String, query: String, baseColor: Color) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = baseColor
        guard !query.isEmpty else { return attr }
        let highlightBg = CodyColors.textAccent.opacity(0.25)
        let totalChars = text.count
        for range in SearchKeywords.hitRanges(in: text, terms: SearchKeywords.terms(query)) {
            let lo = text.distance(from: text.startIndex, to: range.lowerBound)
            let hi = text.distance(from: text.startIndex, to: range.upperBound)
            // Clamp to attr length; `AttributedString.index(_:offsetByCharacters:)`
            // traps on out-of-range, so we guard up front. AttributedString
            // built from a Swift `String` shares the same character count
            // as `text.count` (grapheme-cluster clusters identical), so a
            // single bounds check is enough.
            guard lo >= 0, hi <= totalChars, lo < hi else { continue }
            let attrLo = attr.index(attr.startIndex, offsetByCharacters: lo)
            let attrHi = attr.index(attr.startIndex, offsetByCharacters: hi)
            let r = attrLo..<attrHi
            attr[r].backgroundColor = highlightBg
            attr[r].foregroundColor = CodyColors.textAccent
            attr[r].inlinePresentationIntent = .stronglyEmphasized
        }
        return attr
    }


    private func relativeDate(_ date: Date) -> String {
        PerfTrace.measure("SessionRow.relativeDate") {
            Self.relativeDateImpl(date)
        }
    }

    // [T-ios-sessionlist-time-i18n] Row timestamps were hardcoded English
    // ("Yesterday", "N min ago", raw "M/d") while the section headers around
    // them localize via LocalizedStringKey — a zh UI showed "昨天" headers
    // next to "Yesterday" row times. All four phrase keys already exist in
    // Localizable.xcstrings (8 locales); the weekday/short-date fall-backs
    // use localized format templates so e.g. zh renders 7月8日 instead of 7/8.
    // fileprivate (not private): FolderRowHeader shares this exact formatter —
    // a second hand-rolled variant is how the T-ios-sessionlist-time-i18n
    // drift happened the first time.
    static func relativeDateImpl(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let seconds = Int(now.timeIntervalSince(date))
        if calendar.isDateInToday(date) {
            if seconds < 60 {
                return AppLocalized("Just now")
            } else if seconds < 3600 {
                let mins = seconds / 60
                return AppLocalized("\(mins) min ago")
            } else {
                let hrs = seconds / 3600
                return AppLocalized("\(hrs) hr ago")
            }
        } else if calendar.isDateInYesterday(date) {
            return AppLocalized("Yesterday")
        } else {
            let diff = calendar.dateComponents([.day], from: date, to: now)
            let formatter = DateFormatter()
            if let days = diff.day, days < 7 {
                formatter.setLocalizedDateFormatFromTemplate("EEEE")
            } else {
                formatter.setLocalizedDateFormatFromTemplate("Md")
            }
            return formatter.string(from: date)
        }
    }
}

/// Gate the blur + clip + gradient-mask trio on the lock flag so iOS 16
/// doesn't pay the always-on `.mask { Rectangle() }` color-drain cost
/// for unlocked rows (T-ios16-title-color). When unlocked, the row
/// renders with no extra effect modifiers at all.
/// [T-folder-summary-lock] A group's "N chats · <newest member title>" line.
/// The title is the newest member's, so when that member is Face ID locked it
/// is blurred exactly like the member's own row (`LockedRowEffect`) — it used
/// to read in plain text on the group card and in the Move-to-Group picker,
/// defeating the lock. Observes the lock store so it clears in place on unlock
/// and re-blurs on relock. Locked form: the SAME localized "%lld chats · %@"
/// formatted with an empty title (every locale ends in " · %@", so this is the
/// exact prefix, word order included), then the blurred title beside it.
struct FolderSummaryLine: View {
    let count: Int
    let title: String
    let sessionId: String?
    @ObservedObject private var lockStore = SessionLockStore.shared

    var body: some View {
        if let sessionId, lockStore.isVisuallyLocked(sessionId) {
            let noTitle = ""
            HStack(spacing: 4) {
                Text(verbatim: AppLocalized("\(count) chats · \(noTitle)")
                    .trimmingCharacters(in: .whitespaces))
                Text(verbatim: title)
                    .modifier(LockedRowEffect(isLocked: true))
            }
        } else {
            Text("\(count) chats · \(title)")
        }
    }
}

private struct LockedRowEffect: ViewModifier {
    let isLocked: Bool

    func body(content: Content) -> some View {
        if isLocked {
            content
                .blur(radius: 4)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.82),
                            .init(color: .black.opacity(0.0), location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .accessibilityHidden(true)
        } else {
            content
        }
    }
}

/// Row for a session synced from another device.
struct RemoteSessionRow: View {
    let session: ChatSession
    var isFrameless = false
    @ObservedObject private var fontSettings = FontSettings.shared

    var body: some View {
        if isFrameless {
            HStack {
                Text(session.title ?? AppLocalized("Untitled"))
                    .font(.system(size: fontSettings.scaledApp(16)))
                    .foregroundStyle(CodyColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "icloud")
                    .font(.system(size: 12))
                    .foregroundStyle(CodyColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, CodySpacing.sm)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        } else {
            detailedRow
        }
    }

    @ViewBuilder
    private var detailedRow: some View {
        let icon = sessionCategoryBadge(for: session.category)
        HStack(spacing: CodyMetrics.Sidebar.itemSpacing) {
            CodyListIconBadge(systemImage: icon.systemName, tint: icon.tint)

            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(session.title ?? "Untitled")
                    .font(.system(size: fontSettings.scaledApp(16), weight: .semibold))
                    .foregroundStyle(CodyColors.textPrimary)
                    .lineLimit(1)
                Text(session.updatedAt, style: .relative)
                    .font(.system(size: fontSettings.scaledApp(14)))
                    .foregroundStyle(CodyColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SidebarRowBadge(systemImage: "icloud.fill", tint: CodyCategoryTint.blue.color)
                .padding(.trailing, CodyMetrics.Sidebar.badgeTrailingPadding)
        }
        .padding(.horizontal, CodyMetrics.Sidebar.rowPaddingH)
        .padding(.vertical, CodySpacing.xxs)
        .frame(minHeight: CodyMetrics.Sidebar.rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SidebarRowBadge: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: CodyMetrics.Sidebar.statusIndicatorSlot,
                   height: CodyMetrics.Sidebar.statusIndicatorSlot)
            .background(CodyColors.bgListIcon, in: Circle())
            .accessibilityHidden(true)
    }
}

struct SidebarUnreadDot: View {
    var body: some View {
        Circle()
            .fill(CodyColors.statusErrorText)
            .frame(width: CodySpacing.sm, height: CodySpacing.sm)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SidebarRowActivity: View {
    let isSuspended: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isSuspended {
                SuspendedRing(color: CodyColors.statusWarningText)
            } else if reduceMotion {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                SpinningRing(color: tint)
            }
        }
        .frame(width: CodyMetrics.Sidebar.statusIndicatorSlot, height: CodyMetrics.Sidebar.statusIndicatorSlot)
        .accessibilityHidden(true)
    }
}

/// A dashed circle ring indicating a session is suspended (waiting for a concurrency slot).
private struct SuspendedRing: View {
    let color: Color

    var body: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }
}
