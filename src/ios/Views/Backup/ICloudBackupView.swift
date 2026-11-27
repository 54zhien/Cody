#if DEBUG
import SwiftUI

struct ICloudBackupView: View {
    @StateObject private var manager = ICloudBackupManager.shared
    @State private var showError: String?
    @State private var showRestoreConfirm: ICloudBackupManager.BackupEntry?

    var body: some View {
        List {
            // MARK: - Status & Backup Actions
            Section {
                if !manager.isICloudAvailable {
                    HStack(spacing: CodySpacing.md) {
                        CodySettingsIconBadge(systemImage: "exclamationmark.icloud", tint: .red)
                        Text("iCloud is not available")
                            .font(CodyTypography.bodyLarge)
                            .foregroundStyle(CodyColors.textPrimary)
                        Spacer()
                        CodyStatusPill("Unavailable", tone: .error)
                    }
                    .codyGroupedRow()
                } else {
                    HStack(spacing: CodySpacing.md) {
                        CodySettingsIconBadge(systemImage: "checkmark.icloud.fill", tint: .green)
                        Text("iCloud connected")
                            .font(CodyTypography.bodyLarge)
                            .foregroundStyle(CodyColors.textPrimary)
                        Spacer()
                        CodyStatusPill("Connected", tone: .success, dotColor: CodyColors.connectionReady)
                    }
                    .codyGroupedRow()
                }
            }

            if manager.isICloudAvailable {
                Section {
                    ForEach(ICloudBackupManager.BackupCategory.allCases) { category in
                        Button {
                            performBackup(category: category)
                        } label: {
                            HStack(spacing: CodySpacing.md) {
                                CodySettingsIconBadge(
                                    systemImage: category.systemImage,
                                    tint: categoryTint(for: category)
                                )
                                VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                                    Text(category.displayName)
                                        .font(CodyTypography.bodyLarge)
                                        .foregroundStyle(CodyColors.textPrimary)
                                    Text(category.description)
                                        .font(CodyTypography.bodySmall)
                                        .foregroundStyle(CodyColors.textSecondary)
                                }
                                Spacer()
                                if manager.isBackingUp {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .padding(.vertical, CodySpacing.xxs)
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .disabled(manager.isBackingUp || manager.isRestoring)
                        .codyGroupedRow()
                    }

                    if manager.isBackingUp {
                        progressRow
                            .codyGroupedRow()
                    }
                } header: {
                    Text("Backup")
                        .settingsSectionHeading()
                }
            }

            if manager.isRestoring {
                Section {
                    progressRow
                        .codyGroupedRow()
                } header: {
                    Text("Restoring")
                        .settingsSectionHeading()
                }
            }

            // MARK: - Available Backups
            let grouped = Dictionary(grouping: manager.availableBackups, by: \.deviceName)
            let sortedDevices = grouped.keys.sorted()

            ForEach(sortedDevices, id: \.self) { device in
                Section {
                    ForEach(grouped[device] ?? []) { entry in
                        backupRow(entry)
                            .codyGroupedRow()
                    }
                } header: {
                    Text(device)
                        .settingsSectionHeading()
                }
            }

            if manager.availableBackups.isEmpty && manager.isICloudAvailable {
                Section {
                    Text("No backups found")
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textSecondary)
                        .codyGroupedRow()
                }
            }

            Section {
                // empty section for footer
            } footer: {
                Text("Backups are stored in iCloud Drive and sync across your devices. Restoring will replace your current local data.")
                    .settingsSectionFooter()
            }
        }
        .codyGroupedListCanvas()
        .navigationTitle("iCloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await manager.listBackups()
        }
        .refreshable {
            await manager.listBackups()
        }
        .alert("Restore Backup", isPresented: .init(
            get: { showRestoreConfirm != nil },
            set: { if !$0 { showRestoreConfirm = nil } }
        )) {
            Button("Cancel", role: .cancel) { showRestoreConfirm = nil }
            Button("Restore", role: .destructive) {
                if let entry = showRestoreConfirm {
                    performRestore(entry: entry)
                }
            }
        } message: {
            if let entry = showRestoreConfirm {
                Text("This will replace your current \(entry.category.displayName.lowercased()) data with the backup from \(entry.date.formatted(date: .abbreviated, time: .shortened)). This cannot be undone.")
            }
        }
        .alert("Error", isPresented: .init(
            get: { showError != nil },
            set: { if !$0 { showError = nil } }
        )) {
            Button("OK") { showError = nil }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
    }

    // MARK: - Progress & Category Visuals

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: CodySpacing.sm) {
            HStack {
                Text(manager.statusMessage)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                Spacer()
                Text(manager.progress, format: .percent.precision(.fractionLength(0)))
                    .font(CodyTypography.labelMedium)
                    .monospacedDigit()
                    .foregroundStyle(CodyColors.textSecondary)
            }
            CodyProgressBar(progress: manager.progress)
        }
        .padding(.vertical, CodySpacing.xs)
    }

    private func categoryTint(for category: ICloudBackupManager.BackupCategory) -> CodyCategoryTint {
        switch category {
        case .sessions: return .blue
        case .skillsAndMemories: return .purple
        case .full: return .orange
        }
    }

    // MARK: - Backup Row

    private func backupRow(_ entry: ICloudBackupManager.BackupEntry) -> some View {
        HStack(spacing: CodySpacing.md) {
            CodySettingsIconBadge(
                systemImage: entry.category.systemImage,
                tint: categoryTint(for: entry.category)
            )

            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(entry.category.displayName)
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                HStack(spacing: CodySpacing.sm) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(entry.fileSize.formattedFileSize)
                        .monospacedDigit()
                }
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
            }
        }
        .padding(.vertical, CodySpacing.xxs)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteBackup(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                showRestoreConfirm = entry
            } label: {
                Label("Restore", systemImage: "arrow.counterclockwise")
            }
            .tint(CodyColors.textAccent)
        }
        .contextMenu {
            Button {
                showRestoreConfirm = entry
            } label: {
                Label("Restore", systemImage: "arrow.counterclockwise")
            }
            .disabled(manager.isRestoring || manager.isBackingUp)

            Button(role: .destructive) {
                deleteBackup(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func performBackup(category: ICloudBackupManager.BackupCategory) {
        Task {
            do {
                try await manager.backup(category: category)
            } catch {
                showError = error.localizedDescription
            }
        }
    }

    private func performRestore(entry: ICloudBackupManager.BackupEntry) {
        Task {
            do {
                try await manager.restore(from: entry)
            } catch {
                showError = error.localizedDescription
            }
        }
    }

    private func deleteBackup(_ entry: ICloudBackupManager.BackupEntry) {
        do {
            try manager.deleteBackup(entry)
        } catch {
            showError = error.localizedDescription
        }
    }
}
#endif
