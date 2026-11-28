//
//  ContentView+SectionHeaders.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  ContentView, section headers: the multi-select row, date and folder section
//  headers (folder card, collapse, menu), folder picker items, and folder
//  actions (new chat in a folder, delete a folder with its sessions).
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

extension ContentView {
    // MARK: - Selectable Row

    func selectableRow(_ session: ChatSession) -> some View {
        let isSelected = selectedIds.contains(session.id)
        return Button {
            if isSelected {
                selectedIds.remove(session.id)
            } else {
                selectedIds.insert(session.id)
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? CodyColors.textAccent : CodyColors.textTertiary)
                    .accessibilityHidden(true)
                SessionRow(session: session, isFrameless: !isWideLayout)
            }
            .padding(.leading, CodyMetrics.Sidebar.indicatorLeadingPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Section Header

    @ViewBuilder
    func sectionHeader(index: Int, group: SidebarGroup) -> some View {
        if isSelecting {
            let groupIds = Set(group.ids)
            let allSelected = !groupIds.isEmpty && groupIds.isSubset(of: selectedIds)
            Button {
                if allSelected {
                    selectedIds.subtract(groupIds)
                } else {
                    selectedIds.formUnion(groupIds)
                }
            } label: {
                HStack(spacing: CodyMetrics.Sidebar.pinnedIconSpacing) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(allSelected ? CodyColors.textAccent : CodyColors.textTertiary)
                        .accessibilityHidden(true)
                    // group.label is a stable English key (used for logic like
                    // == "Pinned"); localize only at display via LocalizedStringKey.
                    // Folder names are user data — render verbatim, not as a key.
                    if group.folderId != nil {
                        Text(verbatim: group.label)
                    } else {
                        Text(LocalizedStringKey(group.label))
                    }
                }
                .modifier(SidebarSectionHeaderStyle())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(allSelected ? .isSelected : [])
            .listRowInsets(EdgeInsets())
        } else if index > 0 || group.label == "Pinned" {
            HStack(spacing: CodyMetrics.Sidebar.pinnedIconSpacing) {
                if group.label == "Pinned" {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                }
                // group.label stays an English key for logic; LocalizedStringKey
                // resolves the display string per system language.
                Text(LocalizedStringKey(group.label))
            }
            .modifier(SidebarSectionHeaderStyle())
            .background(
                RoundedRectangle(cornerRadius: CodyRadius.md)
                    .fill(dropTargetFolderId == "" ? CodyColors.textAccent.opacity(0.18) : Color.clear)
            )
            // Dropping on a date-bucket header moves the sessions OUT of any
            // folder — the drag gesture works both directions, otherwise
            // moving out would still require a trip through the menu.
            .dropDestination(for: String.self) { sessionIds, _ in
                Task { @MainActor in
                    await ChatStore.shared.setFolder(nil, forSessions: sessionIds)
                    refreshSessionList()
                }
                return true
            } isTargeted: { over in
                if over {
                    dropTargetFolderId = ""
                } else if dropTargetFolderId == "" {
                    dropTargetFolderId = nil
                }
            }
        }
    }

    /// Display aggregates for the Move-to-Group picker rows: the same
    /// composed icon glyphs and member count the home group card shows, plus
    /// the subtitle context — the folder's description when one is set,
    /// otherwise the newest member's title (mirroring the card's summary).
    /// Computed once per sheet presentation, not per row.
    ///
    /// [T-folder-picker-recency] Ordered most recently active first
    /// (`FolderPickerOrder`), so the group a session most likely belongs in is
    /// at the top. Only this picker is reordered; the home list keeps its own
    /// group order.
    func folderPickerItems() -> [FolderPickerSheet.FolderItem] {
        let byFolder = Dictionary(grouping: sessions.filter { $0.folderId != nil },
                                  by: { $0.folderId! })
        var activity: [String: Date] = [:]
        let items = folders.map { folder in
            let m = (byFolder[folder.id] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            activity[folder.id] = FolderPickerOrder.lastActive(
                folderUpdatedAt: folder.updatedAt, folderCreatedAt: folder.createdAt,
                newestMemberUpdatedAt: m.first?.updatedAt)
            // Top-3 DISTINCT category glyphs by recency — same rule as
            // groupedSessionIDs, so the picker icon matches the home card.
            var glyphs: [FolderGlyph] = []
            var seenCategories = Set<String>()
            for s in m where seenCategories.insert(s.category ?? "").inserted {
                let icon = sessionCategoryIcon(for: s.category)
                glyphs.append(FolderGlyph(systemName: icon.systemName, color: icon.color))
                if glyphs.count == 3 { break }
            }
            let desc = folder.desc?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return FolderPickerSheet.FolderItem(
                folder: folder,
                glyphs: glyphs,
                count: m.count,
                subtitle: desc.isEmpty ? m.first?.title : desc,
                subtitleSessionId: desc.isEmpty ? m.first?.id : nil)
        }
        return FolderPickerOrder.byRecentActivity(items) { activity[$0.folder.id] ?? .distantPast }
    }

    /// Folder section header: composed icon + name + count + collapse chevron,
    /// with the collapsed-state status passthrough (running / paused / unread).
    ///
    /// The status badges appear ONLY when collapsed: expanded members carry
    /// their own indicators, and duplicating them in the header would leave
    /// the user guessing which row a header "!" refers to. Collapsing is what
    /// hides the members' state — that's exactly when a proxy is needed.
    /// Folder cards share the session rows' icon size and alignment.
    /// `scrollProxy` is forwarded to `toggleFolderCollapsed` so an expand can
    /// re-anchor this header after the accordion removes the previously-open
    /// folder's rows ([T-ios-folder-accordion-scroll-anchor]).
    func folderSectionHeader(
        _ group: SidebarGroup,
        scrollProxy: ScrollViewProxy? = nil,
        frameless: Bool = false
    ) -> some View {
        // Content + onTapGesture instead of a Button: the Button's own
        // long-press handling raced the contextMenu recognizer on some
        // platforms (long-press on the card did not reliably pop the menu).
        // With a bare tap gesture the long-press belongs to the contextMenu
        // alone; the accessibility action keeps the card activatable for
        // AX clients and the debug tap harness.
        Group {
            if frameless {
                novaFolderLabel(group)
            } else {
                folderCardLabel(group)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let fid = group.folderId { toggleFolderCollapsed(fid, scrollProxy: scrollProxy) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(searchResultsActive ? Text("") : (group.isCollapsed ? Text("Expand") : Text("Collapse")))
        .accessibilityAction {
            if let fid = group.folderId { toggleFolderCollapsed(fid, scrollProxy: scrollProxy) }
        }
        // Re-anchor the folder after another expanded section collapses.
        .background {
            if let fid = group.folderId {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { folderHeaderTopY[fid] = geo.frame(in: .global).minY }
                        .onChange(of: geo.frame(in: .global).minY) { folderHeaderTopY[fid] = $0 }
                }
            }
        }
        .background {
            if let fid = group.folderId, !group.isCollapsed, !group.ids.isEmpty {
                FolderHeaderVisibilityProbe(
                    folderId: fid,
                    thresholdY: folderMiniBarTopY,
                    onVisibilityChange: setFolderHeaderOffscreen)
            }
        }
        .id("folderHeader-\(group.folderId ?? "")")
        .listRowInsets(EdgeInsets())
        .dropDestination(for: String.self) { sessionIds, _ in
            guard let fid = group.folderId else { return false }
            Task { @MainActor in
                await ChatStore.shared.setFolder(fid, forSessions: sessionIds)
                refreshSessionList()
            }
            return true
        } isTargeted: { over in
            if over {
                dropTargetFolderId = group.folderId
            } else if dropTargetFolderId == group.folderId {
                dropTargetFolderId = nil
            }
        }
        .contextMenu { folderMenu(group) }
    }

    private func novaFolderLabel(_ group: SidebarGroup) -> some View {
        HStack(spacing: 14) {
            CodyIconView(.folder, size: 21)
                .accessibilityHidden(true)
            if searchResultsActive {
                Text(SessionRow.highlightedAttributedString(
                    text: group.label, query: searchQuery, baseColor: CodyColors.textPrimary))
                    .lineLimit(1)
            } else {
                Text(verbatim: group.label)
                    .lineLimit(1)
            }
            Spacer(minLength: CodySpacing.sm)
            if group.isCollapsed && group.anyActive {
                SidebarRowActivity(isSuspended: false, tint: CodyColors.textAccent)
            }
            if group.isCollapsed && group.anyPaused {
                SidebarRowBadge(systemImage: "pause.fill", tint: CodyColors.statusWarningText)
            }
            if group.isCollapsed && group.anyUnread { SidebarUnreadDot() }
            if !searchResultsActive {
                CodyIconView(group.isCollapsed ? .chevronRight : .chevronDown, size: 13)
                    .foregroundStyle(CodyColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(CodyColors.textPrimary)
        .padding(.trailing, CodySpacing.sm)
        .frame(minHeight: 48)
        .background {
            if dropTargetFolderId == group.folderId {
                RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                    .fill(CodyColors.textAccent.opacity(0.12))
            }
        }
    }

    private func folderCardLabel(_ group: SidebarGroup) -> some View {
        HStack(spacing: CodyMetrics.Sidebar.itemSpacing) {
                FolderComposedIcon(glyphs: group.glyphs)

                VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                    // Folder names are user data — verbatim Text, never a
                    // LocalizedStringKey lookup.
                    // [T-search-folder-expand] A folder-name hit is highlighted
                    // like a title hit on a session row.
                    Group {
                        if searchResultsActive,
                           SearchKeywords.firstHit(in: group.label, terms: SearchKeywords.terms(searchQuery)) != nil {
                            Text(SessionRow.highlightedAttributedString(
                                text: group.label, query: searchQuery, baseColor: CodyColors.textPrimary))
                        } else {
                            Text(group.label).foregroundStyle(CodyColors.textPrimary)
                        }
                    }
                    .font(CodyTypography.titleMedium)
                    .lineLimit(1)
                    Group {
                        if searchResultsActive {
                            // In a result set the members are the matches.
                            Text("\(group.totalCount) matching chats")
                        } else if let title = group.summaryTitle {
                            FolderSummaryLine(count: group.totalCount, title: title,
                                              sessionId: group.summarySessionId)
                        } else if group.totalCount > 0 {
                            Text("\(group.totalCount) chats")
                        } else {
                            Text("Empty group")
                        }
                    }
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textSecondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: CodySpacing.xxs) {
                    if let date = group.latestDate {
                        Text(SessionRow.relativeDateImpl(date))
                            .font(CodyTypography.sectionHeader)
                            .foregroundStyle(CodyColors.textTertiary)
                            .lineLimit(1)
                    }
                    HStack(spacing: CodyMetrics.Sidebar.pinnedIconSpacing) {
                        if group.isFolderPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                        }
                        // [T-search-folder-expand] Search results keep folders open.
                        if !searchResultsActive {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(group.isCollapsed ? -90 : 0))
                        }
                    }
                    .foregroundStyle(CodyColors.textTertiary)
                    .accessibilityHidden(true)
                }

                if group.isCollapsed && (group.anyActive || group.anyPaused || group.anyUnread) {
                    VStack(spacing: CodySpacing.xxs) {
                        if group.anyActive {
                            SidebarRowActivity(isSuspended: false, tint: group.glyphs.first?.color ?? CodyColors.textSecondary)
                        }
                        if group.anyPaused {
                            SidebarRowBadge(systemImage: "pause.fill", tint: CodyColors.statusWarningText)
                        }
                        if group.anyUnread {
                            SidebarUnreadDot()
                        }
                    }
                    .frame(width: CodyMetrics.Sidebar.statusIndicatorSlot)
                    .padding(.trailing, CodyMetrics.Sidebar.badgeTrailingPadding)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, CodyMetrics.Sidebar.rowPaddingH - CodySpacing.xsPlus)
            .padding(.vertical, CodySpacing.xxs)
            .frame(minHeight: CodyMetrics.Sidebar.rowMinHeight)
            .textCase(nil)
            .contentShape(Rectangle())
            .modifier(FolderCardBackground(
                isDropTarget: dropTargetFolderId == group.folderId,
                isExpanded: !group.isCollapsed && !group.ids.isEmpty))
            .padding(.horizontal, CodySpacing.xsPlus)
            .padding(.top, CodySpacing.xs)
            .padding(.bottom, (group.isCollapsed || group.ids.isEmpty) ? CodySpacing.xs : 0)
    }

    @ViewBuilder
    private func folderMenu(_ group: SidebarGroup) -> some View {
            if let fid = group.folderId, let folder = folders.first(where: { $0.id == fid }) {
                Button {
                    Task { @MainActor in
                        await ChatStore.shared.toggleFolderPin(fid)
                        refreshSessionList()
                    }
                } label: {
                    Label(LocalizedStringKey(folder.isPinned ? "Unpin" : "Pin"),
                          systemImage: folder.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    renameFolderText = folder.name
                    // [T-folder-rename-desc-wipe] Seed the description too.
                    // Both fields are shared @State that outlive the dialog, and
                    // `onRename` ALWAYS passes the desc field through (empty
                    // clears the stored value, by design). Leaving this unseeded
                    // meant the field opened blank — or holding whatever was
                    // typed for a previously renamed folder — so a rename that
                    // only touched the NAME silently wiped that folder's
                    // description. Repeat across folders and every description
                    // disappears, which reads as "renaming one group overwrote
                    // them all".
                    renameFolderDesc = folder.desc ?? ""
                    folderToRename = folder
                } label: {
                    Label("Rename Group", systemImage: "square.and.pencil")
                }
                Button {
                    newChatInFolder(fid)
                } label: {
                    Label("New Chat in Group", systemImage: "plus.bubble")
                }
                Divider()
                // Dissolve is deliberately NOT destructive-tinted: it touches
                // no user data (sessions move back to the main list). Tinting
                // it red would train the eye to read it as the deleting item.
                Button {
                    folderToDissolve = folder
                } label: {
                    Label("Dissolve Group", systemImage: "folder.badge.minus")
                }
                Divider()
                // The one destructive item, last, with the count in the title
                // so the consequence is visible in the menu itself, not only
                // in the confirmation sheet.
                Button(role: .destructive) {
                    requestDeleteFolderWithSessions(folder)
                } label: {
                    Label("Delete Group & \(group.totalCount) Sessions", systemImage: "trash")
                }
            }
    }

    /// "New chat in folder": file the just-promoted draft. Separate from the
    /// draft-bookkeeping onReceive (which is gated on isWideLayout) because
    /// this must run on iPhone too. The notification can arrive off-main
    /// (ChatStore actor executor) — all state access happens inside the
    /// MainActor hop. Extracted to a method so the body's modifier chain
    /// stays type-checkable.
    func handleSessionCreatedForPendingFolder(_ note: Notification) {
        guard let newId = note.object as? String else { return }
        let noteDraftId = (note.userInfo as? [String: String])?["draftId"]
        Task { @MainActor in
            guard let pending = pendingFolderDraft else { return }
            guard noteDraftId == pending.draftId else {
                // Some other draft was promoted — ours was abandoned. Drop the
                // intent so it can never mis-file a later unrelated chat.
                if noteDraftId != nil { pendingFolderDraft = nil }
                return
            }
            pendingFolderDraft = nil
            _ = await ChatStore.shared.setFolderIfUnfiled(pending.folderId, forSession: newId)
            refreshSessionList()
        }
    }

    /// Folder-header menu: start a new chat that lands inside the folder.
    /// The folder assignment is deferred to draft promotion (see
    /// pendingFolderDraft); the folder is auto-expanded so the new session
    /// doesn't appear to vanish into a collapsed section.
    private func newChatInFolder(_ folderId: String) {
        if collapsedFolderIds.contains(folderId) { toggleFolderCollapsed(folderId) }
        let draftId = Self.makeNewSessionId()
        pendingFolderDraft = (draftId: draftId, folderId: folderId)
        // [T-nav-ghost-row-link] From the home list: replace, never append.
        switchToSession(draftId)
    }

    /// Folder-header menu: delete the folder AND every member session. Reuses
    /// the multi-select delete chain (computeDeleteInfo → DeleteConfirmSheet →
    /// deleteSelectedSessions) rather than a bespoke path — the delete chain
    /// owns session files, tombstones and sync, and re-implementing it would
    /// mean re-earning its correctness.
    private func requestDeleteFolderWithSessions(_ folder: ChatFolder) {
        let memberIds = Set(sessions.filter { $0.folderId == folder.id }.map(\.id))
        selectedIds = memberIds
        pendingDeleteFolderId = folder.id
        deleteInfo = nil
        isComputingDelete = true
        showDeleteConfirm = true
        Task { @MainActor in
            let info = await Self.computeDeleteInfoExpanded(for: memberIds)
            deleteInfo = info
            isComputingDelete = false
        }
    }
}
