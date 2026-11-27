//
//  MoveToSessionSheet.swift
//  Cody - chat page (AIChatView)
//
//  "Move to Session": picks the session that receives this chat's composer
//  content (text and attachments).
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI

// MARK: - Move To Session Sheet

struct MoveToSessionSheet: View {
    let currentSessionId: String?
    let onSelect: (String) -> Void
    /// [T-ios-moveto-perf] Rows to show immediately, before the sheet's own
    /// query returns. The caller already holds a loaded list, so the common
    /// case renders populated on the first frame instead of empty-then-filled;
    /// `.task` still runs and replaces this with the authoritative result.
    var initialSessions: [ChatSession] = []
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ChatSession]
    @State private var searchText = ""
    /// [T-ios-moveto-perf] Search results as full rows, not a set of ids.
    ///
    /// This used to be `Set<String>` that `displayedSessions` INTERSECTED with
    /// `sessions`. That was fine while `sessions` was every session, but the
    /// recent-list is now capped — and an intersection would have silently
    /// reduced search to "matches among the newest N", losing the older
    /// sessions that are exactly what someone searches for. Holding the rows
    /// keeps `searchSessions` full-corpus, which is what it always was.
    @State private var searchResults: [ChatSession]?
    @State private var searchTask: Task<Void, Never>?

    /// How many recent sessions the picker loads up front. Search reaches the
    /// whole corpus regardless, so this only bounds the unsearched "Recent"
    /// list — far more than fits on screen, and cheap to fetch.
    private static let recentLimit = 50

    init(currentSessionId: String?,
         initialSessions: [ChatSession] = [],
         onSelect: @escaping (String) -> Void) {
        self.currentSessionId = currentSessionId
        self.initialSessions = initialSessions
        self.onSelect = onSelect
        _sessions = State(initialValue: initialSessions)
    }

    /// Prefix used by ContentView for draft session IDs.
    private static let newSessionPrefix = "__new__"

    private var isSearching: Bool { !searchText.isEmpty }

    private var displayedSessions: [ChatSession] {
        // [T-ios-moveto-perf] While searching, show the search's OWN rows —
        // see `searchResults`. Only the current session and child sessions are
        // filtered out, the same exclusions the recent list applies.
        let source = searchResults ?? sessions
        return source.filter { $0.id != currentSessionId && !$0.isChild }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isSearching {
                    Section {
                        Button {
                            let newId = "\(Self.newSessionPrefix)\(UUID().uuidString)"
                            dismiss()
                            onSelect(newId)
                        } label: {
                            HStack(spacing: CodyMetrics.Sidebar.itemSpacing) {
                                CodyListIconBadge(systemImage: "plus.bubble", tint: .neutral)
                                Text(AppLocalized("New Chat"))
                                    .font(CodyTypography.titleSmall)
                                    .foregroundStyle(CodyColors.textPrimary)
                                Spacer()
                            }
                            .frame(minHeight: CodyControlHeight.standard)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(CodyColors.bgGroupedSurface)
                        .listRowSeparatorTint(CodyColors.separator)
                    }
                }

                Section {
                    ForEach(displayedSessions) { session in
                        let icon = sessionCategoryIcon(for: session.category)
                        Button {
                            dismiss()
                            onSelect(session.id)
                        } label: {
                            HStack(spacing: CodyMetrics.Sidebar.itemSpacing) {
                                categoryBadge(systemName: icon.systemName, color: icon.color)
                                VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                                    highlightedText(
                                        session.title ?? AppLocalized("New Chat"),
                                        font: CodyTypography.titleSmall,
                                        color: CodyColors.textPrimary
                                    )
                                    .lineLimit(1)
                                    highlightedText(
                                        session.lastMessage ?? AppLocalized("No messages yet"),
                                        font: CodyTypography.bodyMedium,
                                        color: CodyColors.textSecondary
                                    )
                                    .lineLimit(1)
                                }
                                Spacer(minLength: CodySpacing.xs)
                                Text(relativeDate(session.updatedAt))
                                    .font(CodyTypography.bodySmall.monospacedDigit())
                                    .foregroundStyle(CodyColors.textTertiary)
                            }
                            .frame(minHeight: CodyControlHeight.standard)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(CodyColors.bgGroupedSurface)
                        .listRowSeparatorTint(CodyColors.separator)
                    }
                } header: {
                    Text(isSearching ? AppLocalized("Results") : AppLocalized("Recent"))
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgGrouped)
            .searchable(text: $searchText, prompt: AppLocalized("Search chats..."))
            .onChange(of: searchText) { _ in scheduleSearch() }
            .navigationTitle(AppLocalized("Move to…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Cancel")) { dismiss() }
                        .foregroundStyle(CodyColors.textSecondary)
                }
            }
        }
        .task {
            // [T-child-session-leak] Agent child sessions are hidden from the
            // main list; they must not be offered as move targets either.
            //
            // [T-ios-moveto-perf] Bounded: this runs on the ChatStore actor and
            // queues behind whatever else holds it (background sync, a
            // streaming turn writing messages), which is what made the sheet
            // sit on a spinner. A capped query does strictly less work in that
            // slot; `initialSessions` covers the wait itself.
            sessions = ChatStore.shared.listSessions(limit: Self.recentLimit)
                .filter { !$0.isChild }
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = await ChatStore.shared.searchSessions(query: query)
            if !Task.isCancelled {
                searchResults = results.map(\.session)
            }
        }
    }

    // MARK: - Highlight

    @ViewBuilder
    private func highlightedText(_ text: String, font: Font, color: Color) -> some View {
        if isSearching, let query = Optional(searchText.trimmingCharacters(in: .whitespaces)),
           !query.isEmpty, SearchKeywords.firstHit(in: text, terms: SearchKeywords.terms(query)) != nil {
            buildHighlighted(text, query: query, font: font, color: color)
        } else {
            Text(text).font(font).foregroundStyle(color)
        }
    }

    private func buildHighlighted(_ text: String, query: String, font: Font, color: Color) -> Text {
        // [T-search-multi-keyword] Every keyword of the query, as in the
        // home list's rows. Ranges are taken on `text` itself (they used to
        // come from a lowercased copy, whose indices need not line up).
        var result = Text("")
        var current = text.startIndex

        for range in SearchKeywords.hitRanges(in: text, terms: SearchKeywords.terms(query)) {
            if current < range.lowerBound {
                result = result + Text(text[current..<range.lowerBound])
                    .font(font).foregroundColor(color)
            }
            result = result + Text(text[range])
                .font(font).foregroundColor(CodyColors.textAccent).bold()
            current = range.upperBound
        }
        if current < text.endIndex {
            result = result + Text(text[current..<text.endIndex])
                .font(font).foregroundColor(color)
        }
        return result
    }

    private func categoryBadge(systemName: String, color: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
        return Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: CodyMetrics.Sidebar.iconSize, height: CodyMetrics.Sidebar.iconSize)
            .background(shape.fill(CodyColors.bgListIcon))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Relative Date

    private func relativeDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let seconds = Int(now.timeIntervalSince(date))
        if calendar.isDateInToday(date) {
            if seconds < 60 {
                return AppLocalized("Just now")
            } else if seconds < 3600 {
                let mins = seconds / 60
                return "\(mins) min ago"
            } else {
                let hrs = seconds / 3600
                return "\(hrs) hr ago"
            }
        } else if calendar.isDateInYesterday(date) {
            return AppLocalized("Yesterday")
        } else {
            let diff = calendar.dateComponents([.day], from: date, to: now)
            if let days = diff.day, days < 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: date)
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}
