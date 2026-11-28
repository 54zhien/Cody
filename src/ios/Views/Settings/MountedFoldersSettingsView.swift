//
//  MountedFoldersSettingsView.swift
//  CodyApp
//
//  Settings screen for managing user-mounted external folders. Lets the user
//  pick a folder from iOS Files (e.g. an Obsidian vault in iCloud Drive),
//  give it a custom name, and mount it at /var/cody/mounts/<name>.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let mountUILogger = AppLogger(category: "MountedFoldersUI")

/// Wrapper so we can drive the Add-Mount sheet via `.sheet(item:)`, which
/// guarantees the URL is present when the sheet is constructed. Using two
/// stacked `.sheet(isPresented:)` modifiers races on first pick: the
/// AddMountSheet is built before `pendingPickedURL` has propagated, so its
/// "Source path" section renders empty until the next attempt.
private struct PendingMount: Identifiable {
    let id = UUID()
    let url: URL
    var name: String
    var allowWrite: Bool
}

struct MountedFoldersSettingsView: View {
    @StateObject private var model = MountedFoldersViewModel()
    @State private var showingPicker = false
    @State private var pendingMount: PendingMount?
    @State private var errorText: String?

    var body: some View {
        CodySettingsScrollPage {
            CodySettingsNovaSection {
                InfoBanner()
                    .settingsNovaControlRow()
            }

            if model.entries.isEmpty {
                CodySettingsNovaSection {
                    VStack(spacing: CodySpacing.smPlus) {
                        Text("No mounted folders")
                            .font(.headline)
                        Text("Tap + to pick a folder from Files (e.g. an Obsidian vault in iCloud Drive).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CodySpacing.lg)
                    .settingsNovaControlRow()
                }
            } else {
                mountList
            }
        }
        .navigationTitle("Mount External Folders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(Text("Mount External Folders"))
                }
                .disabled(model.isAtCapacity)
            }
        }
        .sheet(isPresented: $showingPicker) {
            FolderPicker { url in
                // `UIDocumentPickerViewController` fires its `didPickDocumentsAt`
                // delegate *after* SwiftUI has already started dismissing the
                // sheet, but we still need to wait until the dismissal fully
                // finishes before presenting a second sheet — iOS refuses to
                // stack two sheets, so assigning `pendingMount` synchronously
                // here silently drops the presentation on first try.
                // Hopping to the next run loop tick lets the picker sheet
                // finish leaving the hierarchy first.
                mountUILogger.info("FolderPicker onPick url=\(url.path)")
                DispatchQueue.main.async {
                    let pm = PendingMount(
                        url: url,
                        name: Self.defaultMountName(for: url),
                        allowWrite: true
                    )
                    mountUILogger.info("async assign pendingMount id=\(pm.id.uuidString) url=\(url.path)")
                    pendingMount = pm
                }
            }
        }
        .sheet(item: $pendingMount) { pending in
            // IMPORTANT: read from the `pending` closure parameter, not from
            // `pendingMount?.url` — the Optional state binding can be
            // momentarily nil while SwiftUI re-routes the sheet, which blanks
            // out the Source Path field.
            AddMountSheet(
                sourceURL: pending.url,
                name: Binding(
                    get: { pendingMount?.name ?? pending.name },
                    set: { pendingMount?.name = $0 }
                ),
                allowWrite: Binding(
                    get: { pendingMount?.allowWrite ?? pending.allowWrite },
                    set: { pendingMount?.allowWrite = $0 }
                ),
                onCancel: {
                    pendingMount = nil
                },
                onConfirm: {
                    let current = pendingMount ?? pending
                    do {
                        _ = try model.add(
                            pickedURL: current.url,
                            customName: current.name,
                            userAllowWrite: current.allowWrite
                        )
                    } catch {
                        errorText = error.localizedDescription
                    }
                    pendingMount = nil
                }
            )
        }
        .alert(AppLocalized("Error"),
               isPresented: Binding(get: { errorText != nil },
                                    set: { if !$0 { errorText = nil } })) {
            Button(AppLocalized("OK"), role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    /// Build the MountDetailView context for an external-mount entry.
    private var mountList: some View {
        CodySettingsNovaSection(
            "Mounted Folders",
            footer: model.isAtCapacity
                ? "Mount limit reached. Remove an existing mount before adding a new one."
                : nil
        ) {
            ForEach(model.entries) { entry in
                if entry.id != model.entries.first?.id {
                    CodySettingsNovaDivider(leadingInset: 18)
                }
                HStack(spacing: 0) {
                    NavigationLink {
                        MountDetailView(
                            context: detailContext(for: entry),
                            onDismiss: { model.refresh() }
                        )
                    } label: {
                        MountedFolderRow(
                            entry: entry,
                            state: model.state(for: entry.id),
                            sourceURL: model.resolvedURL(for: entry.id)
                        )
                        .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    SettingsNovaRowMenu(title: "Actions for \(entry.name)") {
                        Button(role: .destructive) {
                            model.remove(id: entry.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .padding(.trailing, CodySpacing.sm)
                }
            }
            CodySettingsNovaDivider(leadingInset: 18)
            LabeledContent("Mounted Folders") {
                Text("\(model.entries.count) / \(MountedFoldersManager.maxMountCount)")
                    .monospacedDigit()
                    .foregroundStyle(model.isAtCapacity ? CodyColors.statusWarningText : CodyColors.textSecondary)
            }
            .settingsNovaControlRow()
        }
    }

    private func detailContext(for entry: MountedFolderEntry) -> MountDetailContext {
        // Host URL for Browse Files goes through the fakefs symlink so the
        // breadcrumb shows /var/cody/mounts/<name>.
        let mountPath = RootfsManager.shared.dataPath
            .appendingPathComponent("var/cody/mounts", isDirectory: true)
            .appendingPathComponent(entry.name)
        return MountDetailContext(
            kind: .external,
            linuxPath: "/var/cody/mounts/\(entry.name)",
            sourceDisplayName: entry.sourceDisplayName,
            hostURL: mountPath,
            subtitle: nil,
            initialName: entry.name,
            canRename: true,
            externalMountId: entry.id,
            isOSWritable: entry.isWritable,
            initialUserAllowWrite: entry.userAllowWrite,
            sharedFolderName: nil,
            initialVisibleInFiles: true,
            isReadOnlyFromFiles: false
        )
    }

    /// Trivial / meaningless segments often appearing at the end of an iCloud
    /// container identifier's reverse-DNS bundle ID (e.g. `iCloud~com~nssurge~inc`
    /// where "inc" is just the company suffix). We skip these when picking a
    /// friendly default mount name.
    private static let trivialSuffixes: Set<String> = [
        "inc", "ltd", "llc", "app", "co", "corp", "gmbh"
    ]

    /// Default mount name suggestion.
    ///
    /// When the user picks an iCloud Drive app folder, `url.lastPathComponent`
    /// is often literally "Documents" because Apple's ubiquity container
    /// structure is:
    ///     .../Mobile Documents/iCloud~<team>~<bundle-parts>/Documents/
    ///
    /// Using "Documents" as the mount name gives no hint about which app the
    /// folder belongs to. We detect that case and instead derive the name
    /// from the parent container, picking the most meaningful segment of the
    /// reverse-DNS bundle ID (e.g. `iCloud~com~nssurge~inc` → `nssurge`, not
    /// `inc`).
    private static func defaultMountName(for url: URL) -> String {
        let lastName = url.lastPathComponent
        let candidate: String
        if lastName == "Documents" {
            // Walk up: parent is the ubiquity container directory.
            let parent = url.deletingLastPathComponent()
            let parentName = parent.lastPathComponent
            if parentName.hasPrefix("iCloud~") {
                // Format: "iCloud~<team>~<bundle-component-1>~<bundle-component-2>..."
                // Drop the "iCloud" prefix and the TLD-like team segment
                // (index 1, usually "com" / "net" / "org" / "io" / "md").
                let parts = parentName.split(separator: "~").map(String.init)
                let remaining = Array(parts.dropFirst(2)) // drop "iCloud" + team
                // Prefer the last segment that isn't a trivial corporate suffix.
                let best = remaining.reversed().first { segment in
                    !Self.trivialSuffixes.contains(segment.lowercased())
                } ?? remaining.last ?? parts.last ?? lastName
                candidate = best
            } else if !parentName.isEmpty {
                // Not an iCloud container but still called Documents —
                // fall back to the parent name for disambiguation.
                candidate = parentName
            } else {
                candidate = lastName
            }
        } else {
            candidate = lastName
        }

        let cleaned = candidate
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? "mount" : cleaned
    }
}

// MARK: - Banner

private struct InfoBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mount external folders")
                .font(.subheadline.weight(.semibold))
            Text("Picked folders are bind-mounted at /var/cody/mounts/<name>. You can browse them in Browse Files and read/write them directly from the iSH shell, just like /var/cody/shared. Up to 10 folders can be mounted at a time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Row

private struct MountedFolderRow: View {
    let entry: MountedFolderEntry
    let state: MountActivationState
    let sourceURL: URL?

    var body: some View {
        HStack(spacing: CodySpacing.md) {
            VStack(alignment: .leading, spacing: CodySpacing.xs) {
                HStack(spacing: CodySpacing.sm) {
                    Text(entry.name)
                        .font(CodyTypography.titleMedium)
                    accessBadge
                }
                Text("/var/cody/mounts/\(entry.name)")
                    .font(CodyTypography.code)
                    .foregroundStyle(CodyColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: "← \(sourceURL?.path ?? entry.sourceDisplayName)")
                    .font(CodyTypography.labelSmall)
                    .foregroundStyle(CodyColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: CodySpacing.sm)
            SettingsNovaDisclosure()
        }
        .padding(.vertical, 2)
    }

    /// Small pill reflecting the effective write state of this mount:
    /// - "R/W": the OS allows writes AND the user allowed writes
    /// - "Locked": the OS allows writes but the user set Allow Writes = off
    /// - "Read-only": the OS itself does not allow writes (user choice n/a)
    @ViewBuilder
    private var accessBadge: some View {
        if !entry.isWritable {
            badgePill(
                text: AppLocalized("Read-only"),
                foreground: CodyColors.statusWarningText,
                background: CodyColors.statusWarningBg
            )
        } else if !entry.userAllowWrite {
            badgePill(
                text: AppLocalized("Locked"),
                foreground: CodyCategoryTint.purple.color,
                background: CodyColors.interactiveSecondaryBg
            )
        } else {
            badgePill(
                text: AppLocalized("R/W"),
                foreground: CodyColors.statusSuccessText,
                background: CodyColors.statusSuccessBg
            )
        }
    }

    private func badgePill(text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(background, in: Capsule())
    }
}

// MARK: - Add mount sheet

private struct AddMountSheet: View {
    let sourceURL: URL?
    @Binding var name: String
    @Binding var allowWrite: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            CodySettingsScrollPage {
                if let url = sourceURL {
                    CodySettingsNovaSection(
                        footer: "The path above is how iOS exposes the folder you picked. Use it to confirm which app this data belongs to."
                    ) {
                        VStack(alignment: .leading, spacing: CodySpacing.xs) {
                            Text("Source path")
                                .font(.footnote)
                                .foregroundStyle(CodyColors.textSecondary)
                            Text(url.path)
                                .font(CodyTypography.code)
                                .foregroundStyle(CodyColors.textPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .settingsNovaControlRow()
                    }
                }

                VStack(alignment: .leading, spacing: CodySpacing.xs) {
                    TextField("name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .settingsNovaField("Mount name")
                    Text("This will be the folder name under /var/cody/mounts/")
                        .settingsNovaFooter()
                }

                CodySettingsNovaSection(
                    "Permissions",
                    footer: "You can change the write permission later from the mount details page."
                ) {
                    Toggle(isOn: $allowWrite) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow writes")
                            Text(allowWrite
                                ? AppLocalized("AI, shell, and Files browser can modify files in this mount.")
                                : AppLocalized("This mount will be exposed as read-only. Useful for reference vaults you don't want the AI to touch."))
                                .font(CodyTypography.bodySmall)
                                .foregroundStyle(CodyColors.textSecondary)
                        }
                    }
                    .tint(.green)
                    .settingsNovaControlRow()
                }

                SettingsNovaEditorActions(
                    title: "Mount",
                    isSaveDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
                    save: onConfirm,
                    cancel: onCancel
                )
            }
            .navigationTitle("New Mount")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Folder picker

private struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MountedFoldersViewModel: ObservableObject {
    @Published private(set) var entries: [MountedFolderEntry] = []
    @Published private(set) var states: [UUID: MountActivationState] = [:]

    var isAtCapacity: Bool {
        entries.count >= MountedFoldersManager.maxMountCount
    }

    init() {
        refresh()
    }

    func refresh() {
        entries = MountedFoldersManager.shared.entries
        states = MountedFoldersManager.shared.activationStates
    }

    func state(for id: UUID) -> MountActivationState {
        states[id] ?? .failed("")
    }

    /// Resolved host URL for a mount, if currently active. Exposed to row views
    /// so they can display the underlying iOS filesystem path.
    func resolvedURL(for id: UUID) -> URL? {
        MountedFoldersManager.shared.resolvedURL(for: id)
    }

    @discardableResult
    func add(pickedURL: URL, customName: String, userAllowWrite: Bool) throws -> MountedFolderEntry {
        // The document picker gives a URL with scope active; start it once more
        // defensively so MountedFoldersManager's bookmarkData call inside succeeds.
        let started = pickedURL.startAccessingSecurityScopedResource()
        defer { if started { pickedURL.stopAccessingSecurityScopedResource() } }
        let entry = try MountedFoldersManager.shared.add(
            pickedURL: pickedURL,
            customName: customName,
            userAllowWrite: userAllowWrite
        )
        refresh()
        return entry
    }

    func remove(id: UUID) {
        MountedFoldersManager.shared.remove(id: id)
        refresh()
    }

    func rename(id: UUID, to newName: String) throws {
        try MountedFoldersManager.shared.rename(id: id, to: newName)
        refresh()
    }

    func setUserAllowWrite(id: UUID, to allow: Bool) {
        MountedFoldersManager.shared.setUserAllowWrite(id: id, to: allow)
        refresh()
    }
}
