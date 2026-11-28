//
//  ContentView+SessionList.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  ContentView, session list: the List / ScrollView that renders the
//  `[SidebarGroup]` sections - session rows, folder sections and "show more"
//  rows for folder search results - for both layouts.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

extension ContentView {
    // MARK: - Session List

    @ViewBuilder
    func sessionList(useNavigationLinks: Bool) -> some View {
        Group {
            if useNavigationLinks {
                stackList
            } else {
                splitList
            }
        }
        // Hardware ⌘F → focus search, available while the session list is on
        // screen (iPad/Mac keyboards). A zero-opacity button carries the
        // shortcut without affecting layout; it lives in the list's view tree so
        // the command only fires when the list is visible, not inside a chat.
        .background {
            if !useNavigationLinks || isNovaDrawerOpen {
                Button(action: focusSearch) { EmptyView() }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        // [T-ios-migration-timer-toolbar-uaf-crash / T-ios-migration-timer-sessionlist-uaf-crash]
        // Own the migration-subtitle refresh driver here, on the stable sidebar list
        // body, instead of on the churny toolbar principal item (see `titleLabel`).
        // This Group has identity-stable lifetime across the sidebar's life — the
        // inner if/else only swaps which List renders, the wrapper itself is never
        // torn down — so the driver isn't rebuilt when the list content changes.
        //
        // The driver is a `.task` async loop, NOT a `Timer.publish().autoconnect()`
        // subscribed via `.onReceive`. The earlier `.onReceive(migrationProgressTimer)`
        // form still crashed (build 1.10(1)): a process-lived publisher's sink is a
        // SwiftUI attribute that AttributeGraph re-creates on every `body` transaction,
        // and a 5s tick delivered while that attribute is being torn down/rebuilt
        // releases the dangling sink closure → use-after-free (KERN_PROTECTION_FAILURE
        // in _AppearanceActionModifier.MergedCallbacks.updateValue → swift_release_dealloc).
        // The `.task` loop has no graph-bound publisher: SwiftUI owns the Task's
        // lifetime by view identity and cancels it deterministically on teardown, so
        // there is no sink to release mid-transaction. The loop also parks while the
        // app is backgrounded (the crash reproduced with the app in the background).
        // refreshMigrationSubtitle is idempotent (Task{@MainActor} + diff-before-assign).
        .task { await migrationSubtitleLoop() }
        // [T-ios-soul-name-sidebar-stale] Refresh the sidebar title from SOUL.md.
        // Moved here off the churny toolbar `titleLabel` Text (which rebuilds on
        // every canOpenSync/soulName/migrationSubtitle/isSelecting change) for the
        // same reason as the migration timer above: this Group's identity is stable
        // across the sidebar's life, so the sink is never torn down mid-transaction
        // and can't drop a .soulMdChanged notification arriving during reconstruction.
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let n = SoulStore.cachedMetadata.name
            soulName = n.isEmpty ? "Cody" : n
        }
    }

    /// Transparent List for the compact drawer.
    /// ScrollViewReader feeds the mini-bar's "back to header" jump; wrapping
    /// the List is inert otherwise (no layout/behavior change).
    // [T-ios-stacklist-metadata-explosion] Split points for the generic type.
    //
    // Crash 2026-08-25 14:34 (iPhone18,1): a 218,971 ms main-thread hang whose
    // stack is entirely swift_getTypeByMangledName / swift_getTypeByMangledNode
    // under this property. That is the runtime INSTANTIATING TYPE METADATA, not
    // evaluating a body — and the type it was decoding is this one: a single
    // 2,146-character mangled name with 32 nested `QOy` modifier wrappers and
    // 13 generic requirements, because every modifier from `.listRowInsets` out
    // to `.toolbar` folds into one recursive generic. Resolving it walks the
    // whole nest, and the cost explodes with depth.
    //
    // The fix is the same one AIChatView.inputFieldOrWaveform already uses for
    // the identical failure (crash 2026-04-17, `AIChatView.inputBar.getter` via
    // __swift_instantiateConcreteTypeFromMangledNameV2): erase at a few chosen
    // seams so the runtime decodes several shallow types instead of one deep
    // one. `AnyView` costs an allocation and drops static-diff information for
    // that subtree — acceptable here precisely because these are the rows and
    // chrome the List already re-identifies by id, and a 219-second hang is not.
    //
    // Do NOT re-inline these. If you add modifiers to the row or the outer
    // chain, add them INSIDE an existing erased helper rather than lengthening
    // the top-level chain, or the nesting depth grows straight back.

    /// One session row with its full modifier stack, erased.
    ///
    /// [T-home-list-lazy-rows] The iPhone row for one id, as a concrete
    /// `SessionStackRow` (one view, fixed type). Runs only for rows the List
    /// actually builds, so the lookups below are per visible row, not per
    /// session in the library.
    private func stackRow(_ sessionId: String, group: SidebarGroup) -> SessionStackRow {
        let storedSession = sessionForRow(sessionId)
        let session = storedSession ?? .missingRowPlaceholder(sessionId)
        let dragSessionID = Self.isNewSessionId(sessionId) ? newSessionRealId : storedSession?.id
        return SessionStackRow(
            session: session,
            isActive: sessionIsRunning(sessionId),
            isSuspended: sidebarConcurrencyManager.isSuspended(sessionId),
            highlightQuery: isSearching ? searchQuery : nil,
            matchSnippet: isSearching ? searchMatchSnippets[sessionId] : nil,
            isRegeneratingTitle: regeneratingTitleSessionId == sessionId,
            inFolder: group.folderId != nil,
            menuActions: menuActions,
            dragSessionID: dragSessionID,
            isHighlighted: novaDestination == .home && isSessionHighlighted(sessionId)
        )
    }

    /// [T-home-list-lazy-rows] The iPad / Mac row for one id; see `stackRow`.
    private func splitRow(_ sessionId: String, group: SidebarGroup) -> SessionSplitRow {
        let session = sessionForRow(sessionId) ?? .missingRowPlaceholder(sessionId)
        // [T-ios-ipad-new-session-contextmenu-broken / GH#30] A persisted draft
        // row keeps the DRAFT id as its tag; its menu targets the REAL id. A
        // never-sent draft (no realId) has no menu.
        let menuSid = Self.isNewSessionId(session.id) ? newSessionRealId : session.id
        return SessionSplitRow(
            session: session,
            isHighlighted: novaDestination == .home && isSessionHighlighted(session.id),
            isActive: sessionIsRunning(session.id),
            isSuspended: sidebarConcurrencyManager.isSuspended(session.id),
            highlightQuery: isSearching ? searchQuery : nil,
            matchSnippet: isSearching ? searchMatchSnippets[session.id] : nil,
            isRegeneratingTitle: regeneratingTitleSessionId == session.id,
            menuSid: menuSid,
            inFolder: group.folderId != nil,
            isLastInFolder: group.isLastMemberRow(sessionId),
            menuActions: menuActions
        )
    }

    /// [T-search-folder-pages] "Show N more" at the foot of a search-expanded
    /// folder whose matches exceed the pages shown. It is the card's bottom
    /// segment, styled like a member row's subtitle line; each tap adds a page.
    @ViewBuilder
    private func searchFolderShowMoreRow(_ group: SidebarGroup) -> some View {
        let row = Button {
            guard let fid = group.folderId else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                searchFolderPages[fid, default: 1] += 1
            }
        } label: {
            HStack(spacing: CodyMetrics.Sidebar.pinnedIconSpacing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Show \(min(group.hiddenMatchCount, Self.searchFolderPageSize)) more (\(group.hiddenMatchCount) left)")
                    .font(CodyTypography.bodyMedium.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(CodyColors.textAccent)
            .padding(.horizontal, CodyMetrics.Sidebar.rowPaddingH)
            .frame(minHeight: CodyMetrics.Sidebar.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .modifier(SelectionDisabledIfAvailable())

        if isWideLayout {
            row.listRowBackground(FolderMemberRowBackground(isLast: true))
        } else {
            row.listRowBackground(Color.clear)
        }
    }

    static let searchFolderPageSize = 20

    // [T-search-folder-pages] How many of a search-expanded folder's `total`
    // matches show after `pages` pages (at least one), and how many remain
    // behind "Show more". 15 → 15/0, 20 → 20/0, 21 → 20/1, 45 → 20/25, then
    // 40/5, then 45/0.
    // Kept byte-identical with CodyTests/Standalone/SearchFolderPagesTests.swift.
    // BEGIN searchFolderPage
    static func searchFolderPage(total: Int, pages: Int, pageSize: Int = searchFolderPageSize)
        -> (shown: Int, remaining: Int) {
        let shown = min(max(0, total), max(1, pages) * max(1, pageSize))
        return (shown, max(0, total) - shown)
    }
    // END searchFolderPage

    /// The folder card row, erased — four modifiers plus a custom modifier that
    /// would otherwise ride along in the same nest as everything else.
    private func erasedFolderSectionHeader(_ group: SidebarGroup,
                                           scrollProxy: ScrollViewProxy?) -> AnyView {
        AnyView(
            folderSectionHeader(group, scrollProxy: scrollProxy, frameless: true)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .modifier(SelectionDisabledIfAvailable())
        )
    }

    private var stackList: some View {
        ScrollViewReader { scrollProxy in
        stackListBody(scrollProxy: scrollProxy)
    }
    }

    private func novaHistoryHeader(_ title: LocalizedStringKey, topPadding: CGFloat = 0) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(CodyColors.textSecondary)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, minHeight: 36 + topPadding, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .modifier(SelectionDisabledIfAvailable())
    }

    @ViewBuilder
    private func novaPinnedSections(_ groups: [SidebarGroup], scrollProxy: ScrollViewProxy) -> some View {
        let pinnedFolders = groups.filter(\.isFolderPinned)
        let pinnedFolderIds = Set(pinnedFolders.compactMap(\.folderId))
        let pinnedChats = sessions.filter { session in
            guard session.isPinned else { return false }
            if let folderId = session.folderId, pinnedFolderIds.contains(folderId) {
                return false
            }
            return true
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
        let pinCount = pinnedFolders.count + pinnedChats.count
        if pinCount > 0 {
            let limit = showsAllNovaPins ? pinCount : 3
            let pinnedGroup = SidebarGroup(
                label: "Pinned",
                ids: pinnedChats.prefix(max(0, limit - pinnedFolders.count)).map(\.id)
            )
            novaHistoryHeader("Pinned", topPadding: 26)
            ForEach(pinnedFolders.prefix(limit)) { group in
                Section {
                    erasedFolderSectionHeader(group, scrollProxy: scrollProxy)
                    ForEach(group.ids, id: \.self) { sessionId in
                        stackRow(sessionId, group: group)
                    }
                }
            }
            ForEach(pinnedGroup.ids, id: \.self) { sessionId in
                stackRow(sessionId, group: pinnedGroup)
            }
            if pinCount > 3 {
                Button {
                    withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                        showsAllNovaPins.toggle()
                        offscreenFolderHeaderIds.removeAll()
                    }
                } label: {
                    HStack(spacing: 14) {
                        CodyIconView(showsAllNovaPins ? .chevronUp : .chevronDown, size: 15)
                            .accessibilityHidden(true)
                        if showsAllNovaPins {
                            Text("Show less")
                        } else {
                            Text("Show all")
                        }
                    }
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(CodyColors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    /// The erased boundary keeps the list's generic type out of the drawer.
    private func stackListBody(scrollProxy: ScrollViewProxy) -> AnyView {
        AnyView(
        List {
            novaDrawerPrimaryNavRows
            if didInitialLoad, sessions.isEmpty, !isSearching, providerStore.modelGroups.isEmpty, !isSelecting {
                novaSetupCard
                    .listRowInsets(EdgeInsets(top: CodySpacing.sm, leading: CodySpacing.md,
                                              bottom: CodySpacing.sm, trailing: CodySpacing.md))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            // [T-ios-session-list-equatable-jank] id-list projection — see splitList.
            // [T-home-list-perf-diag] Times the grouping and opens a pass
            // for the row lookups that follow; see HomeListPerf.
            let perfStart = HomeListPerf.passBegin()
            let groups = groupedSessionIDs(filteredSessions)
            let _ = HomeListPerf.passEnd(site: "sidebar", start: perfStart, groups: groups, sessions: sessions.count,
                                        inputs: homeListPassInputs)
            // [T-ios-foreach-lazyedits-dup-guard] Record the identity sequence
            // ForEach is about to diff. DEBUG-only, transition-gated, and the
            // result is discarded so the ViewBuilder's shape is unchanged.
            // [T-crash-breadcrumbs] Release-safe counts-only breadcrumb.
            let _ = SidebarStructureCrumb.note(groups, site: "sidebar")
            #if DEBUG
            let _ = SidebarIdentityTracer.note(groups, site: "sidebar")
            #endif
            let showPinnedSection = !isSelecting && !isSearching
            if showPinnedSection { novaPinnedSections(groups, scrollProxy: scrollProxy) }
            let chatGroups = showPinnedSection ? groups.filter { group in
                !group.isFolderPinned && (group.folderId != nil || group.label != "Pinned")
            } : groups
            if !isSelecting {
                if isSearching {
                    novaHistoryHeader("Search Results")
                } else if !chatGroups.isEmpty || !remoteDeviceSessions.isEmpty {
                    sessionUnfileDropTarget {
                        novaHistoryHeader("Chats", topPadding: 26)
                    }
                }
            }
            ForEach(Array(chatGroups.enumerated()), id: \.element.id) { index, group in
                Section {
                    if group.folderId != nil, !isSelecting {
                        erasedFolderSectionHeader(group, scrollProxy: scrollProxy)
                    }
                    // [T-home-list-lazy-rows] Every element is exactly ONE view of a
                    // fixed type, so List counts rows from `group.ids` and builds
                    // only the visible ones - see SessionListRows.swift. The mode
                    // is chosen once per section, not inside each row.
                    // [T-ios-session-list-equatable-jank] Rows resolve via the
                    // @State cache (sessionForRow), NOT a captured
                    // [String:ChatSession] — see sessionsByIdCache.
                    if isSelecting {
                        ForEach(group.ids, id: \.self) { sessionId in
                            selectableRow(sessionForRow(sessionId) ?? .missingRowPlaceholder(sessionId))
                                .id("select-\(sessionId)")
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(group.ids, id: \.self) { sessionId in
                            stackRow(sessionId, group: group)
                        }
                    }
                    if group.hiddenMatchCount > 0, !isSelecting {
                        searchFolderShowMoreRow(group)
                    }
                } header: {
                    // Folder groups render their card as the section's first
                    // ROW (above); the header slot serves the date buckets,
                    // the select-mode select-all, and — on the first folder
                    // group only — the "Groups" divider label.
                    if isSelecting {
                        sectionHeader(index: index, group: group)
                    }
                }
            }
            if !isSelecting { remoteDeviceSessionSections }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
        #if DEBUG
        // TEMPORARY scroll-phase markers to bracket the jitter window in the
        // log. Pair with the [ROWH] probe: a [ROWH] line appearing during
        // `decelerating`/`idle` = a self-size correction mid/post-scroll =
        // the visible jump. Remove with the probe. (iOS 18+ only.)
        .modifier(ScrollPhaseProbe())
        #endif
        .opacity(didInitialLoad ? 1 : 0)
        .overlay {
            if didInitialLoad, isSearching, filteredSessions.isEmpty, searchMatchedFolderIds.isEmpty,
               searchMatchedIds != nil, !hasMatchingRemoteSessions {
                Text("No matching chats")
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textSecondary)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) { folderMiniBarOverlay(scrollProxy) }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionToolbar }
        }
        .onChange(of: scrollToId) { id in
            if let id {
                scrollProxy.scrollTo("select-\(id)", anchor: .center)
                scrollToId = nil
            }
        }
        )
    }

    /// Selection-bound List for split (iPad) layout.
    /// ScrollViewReader: same mini-bar jump wiring as stackList.
    private var splitList: some View {
        ScrollViewReader { scrollProxy in
        List(selection: splitSessionSelection) {
            // [T-ios-session-list-equatable-jank] Diff a (label, ids) projection
            // so SwiftUI compares a [String] id list, not a [ChatSession] value
            // array. Rows resolve the model via displaySessionsById.
            // [T-home-list-perf-diag] Times the grouping and opens a pass
            // for the row lookups that follow; see HomeListPerf.
            let perfStart = HomeListPerf.passBegin()
            let groups = groupedSessionIDs(displaySessions)
            let _ = HomeListPerf.passEnd(site: "selection", start: perfStart, groups: groups, sessions: sessions.count,
                                        inputs: homeListPassInputs)
            // [T-ios-foreach-lazyedits-dup-guard] See the sidebar list above.
            // [T-crash-breadcrumbs] Release-safe counts-only breadcrumb.
            let _ = SidebarStructureCrumb.note(groups, site: "selection")
            #if DEBUG
            let _ = SidebarIdentityTracer.note(groups, site: "selection")
            #endif
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    // Folder card as first row — see the sidebar list's
                    // comment: plain-List headers carry platform-specific
                    // chrome and detached the card from its members on
                    // iPad/macOS; row adjacency welds on every platform.
                    if group.folderId != nil, !isSelecting {
                        folderSectionHeader(group, scrollProxy: scrollProxy)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .modifier(SelectionDisabledIfAvailable())
                    }
                    // [T-home-list-lazy-rows] One fixed-type view per id - see the
                    // sidebar list above and SessionListRows.swift.
                    if isSelecting {
                        ForEach(group.ids, id: \.self) { sessionId in
                            selectableRow(sessionForRow(sessionId) ?? .missingRowPlaceholder(sessionId))
                                .id("select-\(sessionId)")
                                .listRowInsets(EdgeInsets())
                        }
                    } else {
                        ForEach(group.ids, id: \.self) { sessionId in
                            splitRow(sessionId, group: group)
                        }
                    }
                    if group.hiddenMatchCount > 0, !isSelecting {
                        searchFolderShowMoreRow(group)
                    }
                } header: {
                    // Folder groups render their card as the section's first
                    // ROW (above); the header slot serves the date buckets,
                    // the select-mode select-all, and — on the first folder
                    // group only — the "Groups" divider label.
                    if group.folderId == nil || isSelecting {
                        sectionHeader(index: index, group: group)
                    } else if group.showsGroupsHeader {
                        Text("Groups")
                            .modifier(SidebarSectionHeaderStyle())
                    }
                }
            }
            if !isSelecting { remoteDeviceSessionSections }

        }
        .modifier(SidebarListCanvas())
        .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 500)
        // [T-macos27-liquid-glass-navbar] See MacOS27GlassWorkaround. Applied to
        // the Mac sidebar List only; the iPhone compact list (the other branch
        // of sessionList) is unaffected and does not get it.
        .modifier(MacOS27OpaqueNavigationBar(background: Material.bar))
        .opacity(didInitialLoad ? 1 : 0)
        .overlay {
            if didInitialLoad, displaySessions.isEmpty, !isSearching, remoteDeviceSessions.isEmpty {
                emptyState
            }
        }
        .overlay(alignment: .top) { folderMiniBarOverlay(scrollProxy) }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isSelecting { novaSplitDestinations }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionToolbar }
            else if !hidesFABForOnboarding(listIsEmpty: displaySessions.isEmpty) { sidebarFABInset }
        }
        // [T-home-fab-keyboard-inset] Same structural immunity as the compact
        // list above — see that call site for the full rationale. On iPad the
        // sidebar column never hosts a keyboard unless the inline search bar
        // is open (the chat column's composer avoidance is its own subtree).
        .ignoresSafeArea(.keyboard, edges: showSearchBar ? [] : .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { sidebarToolbarContent }
        }
    }
}
