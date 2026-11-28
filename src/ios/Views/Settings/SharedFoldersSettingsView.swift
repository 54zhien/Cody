//
//  SharedFoldersSettingsView.swift
//  CodyApp
//
//  Settings screen that lists the three FileProvider-exposed shared directories
//  (shared, skills, memory), lets the user tap each row to browse its contents,
//  and toggles whether each one is visible in the iOS Files app under
//  "On My iPhone → Cody".
//

import SwiftUI
import FileProvider

struct SharedFoldersSettingsView: View {
    @StateObject private var model = SharedFoldersViewModel()

    var body: some View {
        CodySettingsScrollPage {
            CodySettingsNovaSection(
                "Folders",
                footer: "These directories appear in iOS Files under On My iPhone → Cody. Tap a row to see details, browse, or toggle visibility."
            ) {
                ForEach(model.entries) { entry in
                    if entry.id != model.entries.first?.id {
                        CodySettingsNovaDivider(leadingInset: 18)
                    }
                    NavigationLink {
                        MountDetailView(
                            context: detailContext(for: entry),
                            onDismiss: { model.refresh() }
                        )
                    } label: {
                        SharedFolderRow(
                            entry: entry,
                            isVisible: model.isVisible(entry.name)
                        )
                        .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                }
            }
        }
        .navigationTitle("Shared Folders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailContext(for entry: SharedFolderEntry) -> MountDetailContext {
        MountDetailContext(
            kind: .shared,
            linuxPath: entry.linuxPath,
            sourceDisplayName: nil,
            hostURL: entry.hostURL,
            subtitle: nil,
            initialName: entry.displayName,
            canRename: false,
            externalMountId: nil,
            isOSWritable: entry.isWritableFromFiles,
            initialUserAllowWrite: true,
            sharedFolderName: entry.name,
            initialVisibleInFiles: model.isVisible(entry.name),
            isReadOnlyFromFiles: !entry.isWritableFromFiles
        )
    }
}

// MARK: - Row

private struct SharedFolderRow: View {
    let entry: SharedFolderEntry
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(CodyTypography.titleMedium)
                    accessBadge
                    if !isVisible {
                        Text("Hidden")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().strokeBorder(CodyColors.borderHeavy, lineWidth: CodySpacing.px)
                            )
                    }
                }
                Text(entry.linuxPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: CodySpacing.sm)
            SettingsNovaDisclosure()
        }
        .padding(.vertical, 2)
    }

    /// Small pill showing whether Files app access is read/write or read-only.
    @ViewBuilder
    private var accessBadge: some View {
        if entry.isWritableFromFiles {
            Text("R/W")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CodyColors.statusSuccessText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    CodyColors.statusSuccessBg, in: Capsule()
                )
        } else {
            Text("Read-only")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CodyColors.statusWarningText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    CodyColors.statusWarningBg, in: Capsule()
                )
        }
    }
}

// MARK: - Model

struct SharedFolderEntry: Identifiable, Hashable {
    /// UserDefaults key / FileProvider subdir name ("shared", "skills", "memory").
    let name: String
    let displayName: String
    /// Linux path inside iSH (e.g. "/var/cody/shared").
    let linuxPath: String
    /// Host filesystem URL (App Group container) for FileBrowserView.
    let hostURL: URL
    /// Whether the Files app (via FileProvider extension) can write to this
    /// folder. `memory` and `skills` are read-only from Files; `shared` is r/w.
    /// Note: the CodyApp itself always reads/writes all three — this flag only
    /// describes the Files-app-facing surface.
    let isWritableFromFiles: Bool

    var id: String { name }

}

@MainActor
final class SharedFoldersViewModel: ObservableObject {
    @Published private(set) var entries: [SharedFolderEntry]
    @Published private var visibilityState: [String: Bool]

    init() {
        self.entries = Self.buildEntries()
        var state: [String: Bool] = [:]
        for name in SharedFolderVisibility.allFolderNames {
            state[name] = SharedFolderVisibility.isVisible(name)
        }
        self.visibilityState = state
    }

    func isVisible(_ name: String) -> Bool {
        visibilityState[name] ?? true
    }

    func setVisible(_ name: String, to visible: Bool) {
        visibilityState[name] = visible
        SharedFolderVisibility.setVisible(name, to: visible)
        // Signal the FileProvider to re-enumerate so iOS Files reflects the
        // change. This is best-effort — iOS Files may take a moment to refresh.
        SharedFoldersViewModel.signalFileProviderRoot()
    }

    /// Re-read visibility state from the underlying UserDefaults store. Called
    /// by the detail view's onDismiss so the parent list updates after a save.
    func refresh() {
        var state: [String: Bool] = [:]
        for name in SharedFolderVisibility.allFolderNames {
            state[name] = SharedFolderVisibility.isVisible(name)
        }
        self.visibilityState = state
    }

    private static func buildEntries() -> [SharedFolderEntry] {
        let root = AIChatViewModel.codyAppGroupRoot
        return [
            SharedFolderEntry(
                name: "shared",
                displayName: AppLocalized("Shared"),
                linuxPath: "/var/cody/shared",
                hostURL: root.appendingPathComponent("shared", isDirectory: true),
                isWritableFromFiles: true
            ),
            SharedFolderEntry(
                name: "skills",
                displayName: AppLocalized("Skills"),
                linuxPath: "/var/cody/skills",
                hostURL: root.appendingPathComponent("skills", isDirectory: true),
                isWritableFromFiles: false
            ),
            SharedFolderEntry(
                name: "memory",
                displayName: AppLocalized("Memory"),
                linuxPath: "/var/cody/memory",
                hostURL: root.appendingPathComponent("memory", isDirectory: true),
                isWritableFromFiles: false
            ),
        ]
    }

    private static func signalFileProviderRoot() {
        let domainIdentifier = NSFileProviderDomainIdentifier("com.cody.app.files")
        NSFileProviderManager.getDomainsWithCompletionHandler { domains, _ in
            guard let domain = domains.first(where: { $0.identifier == domainIdentifier }) else {
                return
            }
            NSFileProviderManager(for: domain)?.signalEnumerator(for: .rootContainer) { _ in }
        }
    }
}
