//
//  SkillsManagementView.swift
//  CodyApp
//
//  Settings-level skill management: list, import, edit, delete.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sort options for the skills list. Mirrors the file browser's sort menu
/// (FileSortKey) with the two keys that make sense for skills.
enum SkillSortKey: String, CaseIterable, Identifiable {
    case name
    case modified

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .name: return "Name"
        case .modified: return "Date Modified"
        }
    }
}

struct SkillsManagementView: View {
    @ObservedObject private var store = SkillStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showImportSheet = false
    @State private var showSkillsBrowser = false
    @State private var searchQuery = ""
    /// Top toast shared by "Force iCloud Sync All" and "Copy Source URL".
    @State private var toastMessage: String?
    /// Bumped per toast so an older toast's timer cannot clear a newer one.
    @State private var toastToken = 0
    /// Subscribed mirror of `SyncV2Bootstrap.isEnabled` so the
    /// Force-iCloud-Sync menu entry shows / hides reactively when
    /// the user flips the toggle in Settings.
    @AppStorage("cloudSync.v2.enabled") private var iCloudSyncEnabled: Bool = false
    @AppStorage("skillsList.sortKey") private var sortKeyRaw: String = SkillSortKey.name.rawValue
    @AppStorage("skillsList.sortAscending") private var sortAscending: Bool = true

    private var filteredSkills: [Skill] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? store.skills : store.skills.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
        let key = SkillSortKey(rawValue: sortKeyRaw) ?? .name
        let sorted: [Skill]
        switch key {
        case .name:
            sorted = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modified:
            sorted = base.sorted { $0.updatedAt < $1.updatedAt }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        List {
            if store.skills.isEmpty {
                Section {
                    CodyEmptyStateCard(
                        systemImage: "doc.text",
                        title: "No skills installed",
                        subtitle: "No skills installed. Tap + to import a SKILL.md from GitHub or paste one manually."
                    ) {
                        Button {
                            showImportSheet = true
                        } label: {
                            Label(AppLocalized("Import Skill"), systemImage: "square.and.arrow.down")
                                .font(CodyTypography.labelLarge)
                        }
                        .buttonStyle(CodyPrimaryCapsuleButtonStyle())
                    }
                    .codyGroupedRow()
                }
            } else if filteredSkills.isEmpty {
                Section {
                    Text(AppLocalized("No skills match \"\(searchQuery)\"."))
                        .foregroundStyle(CodyColors.textSecondary)
                        .font(CodyTypography.bodyMedium)
                        .codyGroupedRow()
                }
            }

            ForEach(filteredSkills) { skill in
                NavigationLink {
                    SkillDetailView(skillId: skill.id)
                } label: {
                    HStack(spacing: CodySpacing.md) {
                        CodySettingsIconBadge(
                            systemImage: importSourceIconName(skill.importSource),
                            tint: importSourceTint(skill.importSource)
                        )
                        VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                            Text(skill.name)
                                .font(CodyTypography.bodyLarge)
                                .foregroundStyle(CodyColors.textPrimary)
                            if !skill.description.isEmpty {
                                Text(skill.description)
                                    .font(CodyTypography.bodySmall)
                                    .foregroundStyle(CodyColors.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: CodySpacing.sm)
                        Toggle("", isOn: Binding(
                            get: { skill.isEnabled },
                            set: { store.setEnabled(skill.id, enabled: $0) }
                        ))
                        .labelsHidden()
                    }
                    .padding(.vertical, CodySpacing.xxs)
                }
                .codyGroupedRow()
                .modifier(SkillSourceURLContextMenu(url: skill.importSource.copyableURL) {
                    showToast(AppLocalized("Source URL copied"))
                })
            }
            .onDelete { offsets in
                let ids = offsets.map { filteredSkills[$0].id }
                for id in ids { store.deleteSkill(id) }
            }
        }
        .codyGroupedListCanvas()
        .navigationTitle("Skills")
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(AppLocalized("Search skills")))
        .onAppear { store.reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Sort menu — same structure as the file browser's (sort-key
                // picker + direction toggle), persisted via AppStorage.
                Menu {
                    Picker(selection: $sortKeyRaw) {
                        ForEach(SkillSortKey.allCases) { key in
                            Text(key.label).tag(key.rawValue)
                        }
                    } label: {
                        Text("Sort By")
                    }
                    Button {
                        sortAscending.toggle()
                    } label: {
                        Label(
                            sortAscending ? "Ascending" : "Descending",
                            systemImage: sortAscending ? "arrow.up" : "arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel(Text("Sort By"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showImportSheet = true
                    } label: {
                        Label(AppLocalized("Import Skill"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showSkillsBrowser = true
                    } label: {
                        Label(AppLocalized("Cody Skills"), systemImage: "globe")
                    }
                    // Skill iCloud sync is wired through SyncV2; hide the
                    // force-sync entry entirely when the user has the
                    // feature off in Settings (no-op otherwise).
                    if #available(iOS 17.0, *), iCloudSyncEnabled {
                        Divider()
                        Button {
                            forceSyncAllSkills()
                        } label: {
                            Label(AppLocalized("Force iCloud Sync All"), systemImage: "icloud.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppLocalized("Import Skill"))
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportSkillSheet()
        }
        .fullScreenCover(isPresented: $showSkillsBrowser, onDismiss: {
            store.reload()
        }) {
            CodySkillsBrowserView()
        }
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                Text(msg)
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.vertical, CodySpacing.smPlus)
                    .background(CodyColors.interactivePrimaryBg, in: Capsule())
                    .padding(.top, CodySpacing.sm)
                    .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: toastMessage)
    }

    private func forceSyncAllSkills() {
        let count = store.skills.count
        for s in store.skills { store.forceMarkDirty(s.id) }
        SyncCore.shared.scheduleSend(delay: 0.5)
        showToast(AppLocalized("Queued \(count) skills for sync"), seconds: 3)
    }

    private func showToast(_ message: String, seconds: Double = 2) {
        toastToken += 1
        let token = toastToken
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if toastToken == token { toastMessage = nil }
        }
    }

    private func importSourceIconName(_ source: SkillImportSource) -> String {
        switch source {
        case .url: return "link"
        case .file: return "doc"
        case .bundled: return "shippingbox"
        case .session: return "bubble.left.and.text.bubble.right"
        }
    }

    private func importSourceTint(_ source: SkillImportSource) -> CodyCategoryTint {
        switch source {
        case .url: return .blue
        case .file: return .orange
        case .bundled: return .green
        case .session: return .purple
        }
    }
}

// MARK: - Copy Source URL

/// [T-skill-copy-source-url] Long-press "Copy Source URL" for a skill that was
/// installed from a URL. With no URL the view is returned untouched — no empty
/// context menu, so tap / swipe-to-delete / toggle behave exactly as before.
struct SkillSourceURLContextMenu: ViewModifier {
    let url: String?
    /// Menu title; the in-chat MCP detail reuses this for "Copy URL".
    var title: String = AppLocalized("Copy Source URL")
    let onCopied: () -> Void

    func body(content: Content) -> some View {
        if let url {
            content.contextMenu {
                Button {
                    UIPasteboard.general.string = url
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCopied()
                } label: {
                    Label(title, systemImage: "link")
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Import Sheet

private struct ImportSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var importMode: ImportMode = .url
    @State private var urlText = ""
    @State private var pastedContent = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showFilePicker = false

    enum ImportMode: String, CaseIterable {
        case url = "URL"
        case paste = "Paste"
        case file = "File"
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Import Method", selection: $importMode) {
                    ForEach(ImportMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.horizontal, CodySpacing.lg)

                switch importMode {
                case .url:
                    Section {
                        TextField("", text: $urlText, prompt: Text("github.com/user/repo/blob/main/SKILL.md").foregroundColor(CodyColors.textTertiary))
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .tint(CodyColors.textAccent)
                            .codyGroupedRow()
                    } header: {
                        Text("GitHub URL")
                            .settingsSectionHeading()
                    }

                case .paste:
                    Section {
                        TextEditor(text: $pastedContent)
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(CodyColors.bgGroupedSurface)
                            .frame(minHeight: 200)
                            .codyGroupedRow()
                    } header: {
                        Text("SKILL.md Content")
                            .settingsSectionHeading()
                    }

                case .file:
                    Section {
                        Button(AppLocalized("Choose File…")) {
                            showFilePicker = true
                        }
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textAccent)
                        .buttonStyle(CodyPressableButtonStyle())
                        .codyGroupedRow()
                    } footer: {
                        Text(AppLocalized("Supports SKILL.md, .skill, and .zip files."))
                            .settingsSectionFooter()
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(CodyColors.statusErrorText)
                            .font(CodyTypography.bodySmall)
                            .codyGroupedRow()
                    }
                }
            }
            .codyGroupedFormCanvas()
            .navigationTitle(AppLocalized("Import Skill"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if importMode != .file {
                        Button(AppLocalized("Import")) { performImport() }
                            .disabled(isImporting || (importMode == .url ? urlText.isEmpty : pastedContent.isEmpty))
                    }
                }
            }
            .overlay {
                if isImporting {
                    let shape = RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                    ProgressView("Importing…")
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textPrimary)
                        .padding(CodySpacing.lg)
                        .background {
                            if reduceTransparency {
                                shape.fill(CodyColors.bgElevatedPrimary)
                            } else {
                                shape.fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(shape)
                        .overlay {
                            shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                .allowsHitTesting(false)
                        }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                SkillFileDocumentPicker { result in
                    do {
                        switch result {
                        case .text(let content):
                            _ = try SkillStore.shared.importSkill(content: content, source: .file)
                        case .archiveURL(let url):
                            _ = try SkillStore.shared.importFromArchive(at: url)
                            try? FileManager.default.removeItem(at: url)
                        }
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func performImport() {
        errorMessage = nil
        isImporting = true

        Task { @MainActor in
            do {
                switch importMode {
                case .url:
                    _ = try await SkillStore.shared.importFromGitHub(urlString: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
                case .paste:
                    _ = try SkillStore.shared.importSkill(content: pastedContent, source: .file)
                case .file:
                    break // handled by file picker
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

// MARK: - File Picker

/// Callback receives either a plain-text SKILL.md content string or a file URL for archives.
private enum SkillFilePickResult {
    case text(String)
    case archiveURL(URL)
}

private struct SkillFileDocumentPicker: UIViewControllerRepresentable {
    let onImport: (SkillFilePickResult) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.plainText, .zip]
        // .skill files are zip archives with a custom extension
        if let skillType = UTType(filenameExtension: "skill", conformingTo: .zip) {
            types.append(skillType)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImport: onImport) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onImport: (SkillFilePickResult) -> Void
        init(onImport: @escaping (SkillFilePickResult) -> Void) { self.onImport = onImport }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            if ext == "zip" || ext == "skill" {
                // Copy to temp so we can access after security scope ends
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                if let _ = try? FileManager.default.copyItem(at: url, to: tmp) {
                    onImport(.archiveURL(tmp))
                }
            } else if let content = try? String(contentsOf: url, encoding: .utf8) {
                onImport(.text(content))
            }
        }
    }
}

// MARK: - Settings-style row icon

/// A circular colored badge with a white SF Symbol centered inside, used for
/// the skill detail action rows instead of a bare tinted glyph.
/// [T-skill-detail-icons][T-skill-icon-circular] Spec is copied VERBATIM from
/// the main Settings page rows (ContentView Agent Runtime / Appearance
/// sections): 9pt default-weight white glyph in a 21×21 colored circle —
/// keep the two surfaces identical; don't retune one without the other.
private struct SettingsActionIcon: View {
    let systemImage: String
    let tint: CodyCategoryTint

    var body: some View {
        CodySettingsIconBadge(systemImage: systemImage, tint: tint, outline: .circle)
    }
}

// MARK: - Skill Detail View

private struct SkillDetailView: View {
    let skillId: String
    @ObservedObject private var store = SkillStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isUpdating = false
    @State private var showFilePicker = false
    @State private var updateError: String?
    @State private var updatedAgoText: String = ""
    @State private var shareZipURL: URL?
    @State private var editingName: String = ""
    @State private var isEditingName = false
    @State private var showRescanDone = false
    @State private var showForceSyncDone = false
    @State private var showSourceURLCopied = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss
    /// Mirrors `SyncV2Bootstrap.isEnabled` so the per-skill Force iCloud
    /// Sync button shows / hides reactively when the user flips the
    /// iCloud Sync toggle in Settings. Same gating predicate used by
    /// the parent SkillsManagementView plus-menu (commit 47fd61ef).
    @AppStorage("cloudSync.v2.enabled") private var iCloudSyncEnabled: Bool = false

    private var skill: Skill? {
        store.skills.first(where: { $0.id == skillId })
    }

    /// First 5 non-empty lines of the skill body (frontmatter already stripped)
    private var bodyPreview: String {
        guard let skill else { return "" }
        let nonEmpty = skill.body
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lines = Array(nonEmpty.prefix(5))
        let preview = lines.joined(separator: "\n")
        let hasMore = nonEmpty.count > 5
        return hasMore ? preview + "\n…" : preview
    }

    private var skillFiles: [String] {
        store.listSkillFiles(skillId)
    }

    private static func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    /// Latest modification date across all files in the skill directory.
    private var latestFileModDate: Date? {
        let dir = store.skillDirectoryURL(for: skillId)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var latest: Date?
        for case let fileURL as URL in enumerator {
            if let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                if latest == nil || date > latest! { latest = date }
            }
        }
        return latest
    }

    var body: some View {
        List {
            if let skill {
                // ── Meta ──────────────────────────────────────────────
                Section {
                    HStack {
                        Text(AppLocalized("Name"))
                            .font(CodyTypography.bodyLarge)
                            .foregroundStyle(CodyColors.textPrimary)
                        Spacer()
                        if isEditingName {
                            TextField("Skill name", text: $editingName, onCommit: {
                                commitNameEdit()
                            })
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .submitLabel(.done)
                        } else {
                            Text(skill.name)
                                .font(CodyTypography.bodyLarge)
                                .foregroundStyle(skill.name == SkillStore.defaultSkillName ? CodyColors.statusErrorText : CodyColors.textSecondary)
                            Button {
                                editingName = skill.name == SkillStore.defaultSkillName ? "" : skill.name
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(CodyTypography.bodySmall)
                                    .foregroundStyle(CodyColors.iconSecondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Edit"))
                        }
                    }
                    .codyGroupedRow()
                    LabeledContent("Version", value: skill.version)
                        .codyGroupedRow()
                    if let modDate = latestFileModDate {
                        LabeledContent("Last Modified") {
                            Text(Self.relativeTime(modDate))
                                .foregroundStyle(CodyColors.textSecondary)
                        }
                        .codyGroupedRow()
                    }
                    LabeledContent("Source") {
                        switch skill.importSource {
                        case .url(let url):
                            if showSourceURLCopied {
                                Text(AppLocalized("Copied"))
                                    .font(CodyTypography.bodySmall)
                                    .foregroundStyle(CodyColors.statusSuccessText)
                            } else {
                                Text(url)
                                    .font(CodyTypography.bodySmall)
                                    .foregroundStyle(CodyColors.textSecondary)
                                    .lineLimit(1)
                            }
                        case .file:
                            Text(AppLocalized("File import")).foregroundStyle(CodyColors.textSecondary)
                        case .bundled:
                            Text(AppLocalized("Built-in")).foregroundStyle(CodyColors.textSecondary)
                        case .session:
                            Text(AppLocalized("Session created")).foregroundStyle(CodyColors.textSecondary)
                        }
                    }
                    .codyGroupedRow()
                    // [T-skill-copy-source-url] Long-press the Source row; the
                    // URL itself is truncated to one line, so copying is the
                    // only way to get all of it.
                    .modifier(SkillSourceURLContextMenu(url: skill.importSource.copyableURL) {
                        withAnimation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion)) {
                            showSourceURLCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion)) {
                                showSourceURLCopied = false
                            }
                        }
                    })
                    LabeledContent(AppLocalized("Usage")) {
                        let freq = store.usageFrequency(for: skill.id)
                        CodyStatusPill(localized: usageFrequencyLabel(freq), tone: usageFrequencyTone(freq))
                    }
                    .codyGroupedRow()
                }

                // ── Update actions ────────────────────────────────────
                Section {
                    if case .url = skill.importSource {
                        Button { updateFromURL() } label: {
                            HStack(spacing: CodySpacing.md) {
                                Label {
                                    Text("Update from URL")
                                        .font(CodyTypography.bodyLarge)
                                        .foregroundStyle(CodyColors.textPrimary)
                                } icon: {
                                    CodySettingsIconBadge(systemImage: "arrow.triangle.2.circlepath", tint: .green, outline: .circle)
                                }
                                Spacer()
                                if isUpdating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(updatedAgoText)
                                        .foregroundStyle(CodyColors.textSecondary)
                                        .font(CodyTypography.bodySmall)
                                }
                            }
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .disabled(isUpdating)
                        .codyGroupedRow()
                    }

                    Button { showFilePicker = true } label: {
                        Label {
                            Text("Update from File…")
                                .font(CodyTypography.bodyLarge)
                                .foregroundStyle(CodyColors.textPrimary)
                        } icon: {
                            SettingsActionIcon(systemImage: "doc.badge.arrow.up", tint: .blue)
                        }
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .codyGroupedRow()

                    Button {
                        store.rescanFromDisk(skillId)
                        showRescanDone = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showRescanDone = false }
                    } label: {
                        HStack {
                            Label {
                                Text("Rescan from Disk")
                                    .font(CodyTypography.bodyLarge)
                                    .foregroundStyle(CodyColors.textPrimary)
                            } icon: {
                                SettingsActionIcon(systemImage: "arrow.clockwise", tint: .orange)
                            }
                            Spacer()
                            if showRescanDone {
                                Text(AppLocalized("Done"))
                                    .foregroundStyle(CodyColors.statusSuccessText)
                                    .font(CodyTypography.bodySmall)
                            }
                        }
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .codyGroupedRow()

                    // Same iCloud-toggle gate the parent SkillsManagementView
                    // plus-menu uses (47fd61ef). Hide the button outright
                    // when iCloud sync is disabled — the action would no-op
                    // (markDirty + scheduleSend on a disabled engine).
                    if #available(iOS 17.0, *), iCloudSyncEnabled {
                        Button {
                            store.forceMarkDirty(skillId)
                            SyncCore.shared.scheduleSend(delay: 0.5)
                            showForceSyncDone = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showForceSyncDone = false }
                        } label: {
                            HStack {
                                Label {
                                    Text(AppLocalized("Force iCloud Sync"))
                                        .font(CodyTypography.bodyLarge)
                                        .foregroundStyle(CodyColors.textPrimary)
                                } icon: {
                                    SettingsActionIcon(systemImage: "icloud.and.arrow.up", tint: .purple)
                                }
                                Spacer()
                                if showForceSyncDone {
                                    Text(AppLocalized("Queued"))
                                        .foregroundStyle(CodyColors.statusSuccessText)
                                        .font(CodyTypography.bodySmall)
                                }
                            }
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .codyGroupedRow()
                    }
                }

                // ── Body preview ──────────────────────────────────────
                if !bodyPreview.isEmpty {
                    Section {
                        Text(bodyPreview)
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textSecondary)
                            .lineLimit(nil)
                            .codyGroupedRow()
                    } header: {
                        Text("Description")
                            .settingsSectionHeading()
                    }
                }

                // ── File list ─────────────────────────────────────────
                Section {
                    ForEach(skillFiles, id: \.self) { relativePath in
                        NavigationLink {
                            SkillFileDetailView(skillId: skillId, relativePath: relativePath)
                        } label: {
                            Label {
                                Text(relativePath)
                                    .font(CodyTypography.code)
                                    .foregroundStyle(CodyColors.textPrimary)
                            } icon: {
                                CodySettingsIconBadge(systemImage: fileIcon(for: relativePath), tint: .neutral)
                            }
                        }
                        .codyGroupedRow()
                    }
                } header: {
                    Text("Files")
                        .settingsSectionHeading()
                }

                if let updateError {
                    Section {
                        Text(updateError)
                            .foregroundStyle(CodyColors.statusErrorText)
                            .font(CodyTypography.bodySmall)
                            .codyGroupedRow()
                    }
                }

                // ── Delete ───────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label(AppLocalized("Delete Skill"), systemImage: "trash")
                                .font(CodyTypography.bodyLarge)
                                .foregroundStyle(CodyColors.statusErrorText)
                            Spacer()
                        }
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .codyGroupedRow()
                }
            } else {
                Text(AppLocalized("Skill not found."))
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textSecondary)
                    .codyGroupedRow()
            }
        }
        .codyGroupedListCanvas()
        .navigationTitle(skill?.name ?? "Skill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shareSkill() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(skill == nil)
            }
        }
        .onAppear { refreshUpdatedAgo() }
        .sheet(isPresented: Binding(get: { shareZipURL != nil }, set: { if !$0 { cleanupShareZip() } })) {
            if let url = shareZipURL {
                ActivityView(activityItems: [url]) {
                    cleanupShareZip()
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            SkillFileDocumentPicker { result in
                do {
                    switch result {
                    case .text(let newContent):
                        try store.updateSkillContent(skillId, newContent: newContent)
                    case .archiveURL(let url):
                        _ = try store.importFromArchive(at: url)
                        try? FileManager.default.removeItem(at: url)
                    }
                    updateError = nil
                } catch {
                    updateError = error.localizedDescription
                }
            }
        }
        .alert(AppLocalized("Delete Skill"), isPresented: $showDeleteConfirm) {
            Button(AppLocalized("Delete"), role: .destructive) {
                store.deleteSkill(skillId)
                dismiss()
            }
            Button(AppLocalized("Cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalized("Are you sure you want to delete this skill? This action cannot be undone."))
        }
    }

    private func usageFrequencyLabel(_ freq: SkillStore.UsageFrequency) -> String {
        switch freq {
        case .never:  return AppLocalized("Never Used")
        case .low:    return AppLocalized("Low Usage")
        case .regular: return AppLocalized("Regular Usage")
        case .high:   return AppLocalized("High Usage")
        }
    }

    private func usageFrequencyTone(_ freq: SkillStore.UsageFrequency) -> CodyStatusPill.Tone {
        switch freq {
        case .never:   return .neutral
        case .low:     return .accent
        case .regular: return .warning
        case .high:    return .success
        }
    }

    private func commitNameEdit() {
        isEditingName = false
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, let skill, newName != skill.name else { return }
        store.renameSkill(skillId, newName: newName)
    }

    private func fileIcon(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "md":   return "doc.text"
        case "py":   return "doc.plaintext"
        case "sh":   return "terminal"
        case "json": return "curlybraces"
        case "yaml", "yml": return "list.bullet.indent"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        default:     return "doc"
        }
    }

    private func updateFromURL() {
        isUpdating = true
        updateError = nil
        Task { @MainActor in
            do {
                try await store.updateFromURL(skillId)
            } catch {
                updateError = error.localizedDescription
            }
            isUpdating = false
            refreshUpdatedAgo()
        }
    }

    private func cleanupShareZip() {
        // [T-mac-share-save-race] Do NOT delete the exported zip here. On Mac
        // (Designed for iPad) the share popover closes — firing BOTH this
        // sheet-dismiss path and completionWithItemsHandler — BEFORE the
        // out-of-process "Save" folder panel / "Copy" file-promise consumer
        // has actually read the file. Deleting on dismissal raced that
        // consumer: the user picked a folder and nothing landed (and pasting
        // into a mounted folder failed), intermittently — small zips
        // sometimes won the race. Exports live in per-share directories
        // under tmp/ and are swept by sweepStaleSkillExports() after 24h
        // (plus the system's own tmp purge), so nothing leaks.
        shareZipURL = nil
    }

    /// [T-mac-share-save-race] Remove skill-export tmp directories older than
    /// 24h. Called before each new export — by then any pending Save/Copy/
    /// AirDrop consumer of an old export has long finished.
    private static func sweepStaleSkillExports() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for url in entries where url.lastPathComponent.hasPrefix("skill-export-") {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if mod < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func shareSkill() {
        guard let skill else { return }
        let skillDir = store.skillDirectoryURL(for: skill.id)
        let fm = FileManager.default
        Self.sweepStaleSkillExports()
        // [T-mac-share-save-race] Unique per-export directory so consecutive
        // shares of the same skill never overwrite/delete a zip an earlier
        // share's consumer might still be reading.
        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("skill-export-\(UUID().uuidString)", isDirectory: true)
        // Sanitize the name for a filesystem-safe, single-component zip name.
        let safeName = skill.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let zipName = "\(safeName.isEmpty ? "skill" : safeName).zip"
        let zipURL = exportDir.appendingPathComponent(zipName)
        do {
            try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        } catch {
            updateError = "Failed to create zip: \(error.localizedDescription)"
            return
        }
        do {
            let coordinator = NSFileCoordinator()
            var error: NSError?
            // Surface a copy failure instead of swallowing it with `try?` — a
            // missing/empty zip is exactly what produced the empty save.
            var copyError: Error?
            coordinator.coordinate(readingItemAt: skillDir, options: [.forUploading], error: &error) { tempZipURL in
                do {
                    try FileManager.default.copyItem(at: tempZipURL, to: zipURL)
                } catch {
                    copyError = error
                }
            }
            if let error { throw error }
            if let copyError { throw copyError }
            // Verify the zip materialized and is non-empty before presenting
            // the share sheet, so we never vend an empty file.
            let attrs = try FileManager.default.attributesOfItem(atPath: zipURL.path)
            let size = (attrs[.size] as? Int64) ?? 0
            guard size > 0 else {
                throw NSError(domain: "SkillExport", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Exported zip is empty"])
            }
            shareZipURL = zipURL
        } catch {
            updateError = "Failed to create zip: \(error.localizedDescription)"
        }
    }

    private func refreshUpdatedAgo() {
        guard let skill else { updatedAgoText = ""; return }
        let elapsed = Date().timeIntervalSince(skill.updatedAt)
        switch elapsed {
        case ..<60:      updatedAgoText = "just now"
        case ..<3600:    updatedAgoText = "\(Int(elapsed / 60)) min ago"
        case ..<86400:   updatedAgoText = "\(Int(elapsed / 3600)) hr ago"
        default:         updatedAgoText = "\(Int(elapsed / 86400)) days ago"
        }
    }
}

// MARK: - Skill File Detail View

private struct SkillFileDetailView: View {
    let skillId: String
    let relativePath: String

    @ObservedObject private var store = SkillStore.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var content: String = ""
    @State private var hasChanges = false
    @State private var saveError: String?

    private var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    var body: some View {
        TextEditor(text: $content)
            .font(CodyTypography.code)
            .foregroundStyle(CodyColors.textPrimary)
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgGroupedSurface)
            .padding(.horizontal, CodySpacing.sm)
            .background(CodyColors.bgGrouped)
            .onChange(of: content) { _ in hasChanges = true }
            .overlay(alignment: .bottom) {
                if let saveError {
                    let shape = RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
                    Text(saveError)
                        .foregroundStyle(CodyColors.statusErrorText)
                        .font(CodyTypography.bodySmall)
                        .padding(CodySpacing.sm)
                        .background {
                            if reduceTransparency {
                                shape.fill(CodyColors.statusErrorBg)
                            } else {
                                shape.fill(.ultraThinMaterial)
                            }
                        }
                        .clipShape(shape)
                        .padding(CodySpacing.lg)
                }
            }
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasChanges {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalized("Save")) { save() }
                    }
                }
            }
            .onAppear {
                content = store.readSkillFile(skillId, relativePath: relativePath) ?? ""
            }
    }

    private func save() {
        do {
            try store.writeSkillFile(skillId, relativePath: relativePath, content: content)
            hasChanges = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Cody Skills Browser

import WebKit

struct CodySkillsBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var coordinator = SkillBrowserCoordinator()

    var body: some View {
        NavigationStack {
            ZStack {
                SkillBrowserWebView(coordinator: coordinator)
                    .ignoresSafeArea(edges: .bottom)

                // HUD overlay
                if coordinator.hudState != .hidden {
                    VStack {
                        Spacer()
                        hudView
                            .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                        Spacer().frame(height: 60)
                    }
                    .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: coordinator.hudState)
                }
            }
            .navigationTitle("Cody Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalized("Done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Import This")) {
                        coordinator.importCurrentSkill()
                    }
                    .disabled(coordinator.hudState == .importing)
                }
            }
            .alert(AppLocalized("Skill Already Exists"), isPresented: $coordinator.showOverwriteConfirm) {
                Button(AppLocalized("Update"), role: .destructive) {
                    coordinator.confirmOverwrite()
                }
                Button(AppLocalized("Cancel"), role: .cancel) {}
            } message: {
                Text(AppLocalized("\"\(coordinator.pendingOverwriteName)\" is already installed. Update to the latest version?"))
            }
        }
    }

    @ViewBuilder
    private var hudView: some View {
        HStack(spacing: CodySpacing.smPlus) {
            switch coordinator.hudState {
            case .importing:
                ProgressView()
                    .tint(CodyColors.interactivePrimaryLabel)
                Text(AppLocalized("Importing…"))
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
            case .success(let name):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CodyColors.connectionReady)
                    .accessibilityHidden(true)
                Text(AppLocalized("\(name) imported"))
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .lineLimit(1)
            case .error(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(CodyColors.statusErrorText)
                    .accessibilityHidden(true)
                Text(msg)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .lineLimit(2)
            case .hint(let msg):
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(CodyColors.textAccent)
                    .accessibilityHidden(true)
                Text(msg)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .lineLimit(2)
            case .hidden:
                EmptyView()
            }
        }
        .font(CodyTypography.titleSmall)
        .padding(.horizontal, CodySpacing.lg)
        .padding(.vertical, CodySpacing.smPlus)
        .background(CodyColors.interactivePrimaryBg, in: Capsule())
    }
}

// MARK: - Skill Browser Coordinator

@MainActor
private class SkillBrowserCoordinator: ObservableObject {
    enum HUDState: Equatable {
        case hidden, importing, success(String), error(String), hint(String)
    }

    @Published var currentURL: URL?
    @Published var hudState: HUDState = .hidden
    @Published var showOverwriteConfirm = false
    var pendingImportURL: String = ""
    var pendingImportContent: String = ""
    var pendingOverwriteName: String = ""

    func updateURL(_ url: URL?) {
        currentURL = url
    }

    private func isSkillDirectoryURL(_ url: URL) -> Bool {
        let s = url.absoluteString
        guard s.contains("github.com") else { return true } // Non-GitHub, let it try
        if s.hasSuffix("SKILL.md") { return true }
        // Must contain /tree/ or /blob/ with a path after the branch name
        let pattern = #"github\.com/[^/]+/[^/]+/(tree|blob)/[^/]+/.+"#
        if s.range(of: pattern, options: .regularExpression) != nil { return true }
        // Reject known non-skill pages
        let nonSkill = ["/issues", "/pulls", "/pull/", "/actions", "/settings", "/wiki"]
        if nonSkill.contains(where: { s.contains($0) }) { return false }
        return false
    }

    func importCurrentSkill() {
        guard let url = currentURL else { return }
        let urlString = url.absoluteString

        // Check if URL points to a specific skill directory
        if !isSkillDirectoryURL(url) {
            hudState = .hint(AppLocalized("Select a skill folder first"))
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .hint = hudState { hudState = .hidden }
            }
            return
        }

        hudState = .importing

        Task {
            do {
                // Download and parse first to get the real skill name
                let preflight = try await SkillStore.shared.preflightGitHubImport(urlString: urlString)

                // Check if skill already exists
                if SkillStore.shared.skills.contains(where: { $0.id == preflight.id }) {
                    hudState = .hidden
                    pendingImportURL = urlString
                    pendingImportContent = preflight.content
                    pendingOverwriteName = preflight.name
                    showOverwriteConfirm = true
                    return
                }

                // No conflict — import directly
                let skill = try await SkillStore.shared.commitGitHubImport(urlString: urlString, content: preflight.content)
                hudState = .success(skill.name)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .success = hudState { hudState = .hidden }
            } catch {
                hudState = .error(error.localizedDescription)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if case .error = hudState { hudState = .hidden }
            }
        }
    }

    func confirmOverwrite() {
        hudState = .importing
        Task {
            do {
                let skill = try await SkillStore.shared.commitGitHubImport(urlString: pendingImportURL, content: pendingImportContent)
                hudState = .success(skill.name)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .success = hudState { hudState = .hidden }
            } catch {
                hudState = .error(error.localizedDescription)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if case .error = hudState { hudState = .hidden }
            }
        }
    }
}

// MARK: - WKWebView Wrapper

private struct SkillBrowserWebView: UIViewRepresentable {
    let coordinator: SkillBrowserCoordinator

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use mobile UA so GitHub serves mobile-friendly pages with standard URL routing
        config.applicationNameForUserAgent = "CodyApp Mobile Safari"
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true
        // KVO to track URL changes (GitHub SPA uses pushState)
        context.coordinator.observe(webView)
        if let url = URL(string: "https://github.com/54zhien/Cody") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewDelegate {
        WebViewDelegate(coordinator: coordinator)
    }

    class WebViewDelegate: NSObject {
        let coordinator: SkillBrowserCoordinator
        private var urlObservation: NSKeyValueObservation?

        init(coordinator: SkillBrowserCoordinator) {
            self.coordinator = coordinator
        }

        func observe(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.coordinator.updateURL(wv.url)
                }
            }
        }
    }
}

// MARK: - File Activity Item Source

/// Vends a local file (e.g. an exported skill `.zip`) to the share sheet with
/// its concrete file URL **and** UTI declared up front.
///
/// Passing a bare `URL` to `UIActivityViewController` makes "Save to Files" on
/// iPad try to fetch the file through a file-provider domain — which fails for
/// an app-`tmp/` URL (`error fetching file provider domain … (null)`), and the
/// archive UTI isn't handled by the pasteboard fallback (`CopyToPasteboard:
/// Not handling archive UTI`), so the picker saved an empty file. Declaring the
/// item as a file with `dataTypeIdentifierForActivityType` = the file's UTI
/// (`public.zip`) lets the document picker copy the real bytes to the chosen
/// destination. [T-ios-ipad-skill-export-file-empty-save]
private final class FileActivityItemSource: NSObject, UIActivityItemSource {
    private let fileURL: URL
    private let typeIdentifier: String

    init(fileURL: URL) {
        self.fileURL = fileURL
        // Resolve a concrete UTI from the extension; fall back to public.zip
        // (skill exports are always zip archives) then public.data.
        let ext = fileURL.pathExtension
        let resolved = UTType(filenameExtension: ext)
            ?? (ext.lowercased() == "skill" ? UTType.zip : nil)
            ?? UTType.zip
        self.typeIdentifier = resolved.identifier
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewController(_ controller: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        typeIdentifier
    }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        fileURL.lastPathComponent
    }
}

// MARK: - Activity View (UIActivityViewController wrapper)

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Wrap file URLs in a FileActivityItemSource so "Save to Files" gets a
        // declared UTI and copies the real bytes (fixes empty saves on iPad).
        let items: [Any] = activityItems.map { item in
            if let url = item as? URL, url.isFileURL {
                return FileActivityItemSource(fileURL: url)
            }
            return item
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

