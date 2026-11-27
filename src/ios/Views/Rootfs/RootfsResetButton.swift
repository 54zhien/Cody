//
//  RootfsResetButton.swift
//  CodyApp
//
//  Quick reset button component for easy integration
//

import SwiftUI

/// Quick reset button that can be embedded anywhere in the UI
struct RootfsResetButton: View {
    enum Style {
        case compact  // Small icon button
        case normal   // Regular button
        case prominent // Large styled button
    }

    let style: Style
    let showBackupOption: Bool
    @State private var showResetAlert = false
    @State private var showBackupAlert = false
    @State private var isProcessing = false
    @State private var statusMessage: String?

    init(style: Style = .normal, showBackupOption: Bool = true) {
        self.style = style
        self.showBackupOption = showBackupOption
    }

    var body: some View {
        Group {
            switch style {
            case .compact:
                compactButton
            case .normal:
                normalButton
            case .prominent:
                prominentButton
            }
        }
        .disabled(isProcessing)
        .alert("Reset Rootfs?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                performReset(keepBackup: false)
            }
        } message: {
            Text("This will delete the entire rootfs. All data will be lost. The app will need to restart.")
        }
        .alert("Reset with Backup?", isPresented: $showBackupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset & Backup", role: .destructive) {
                performReset(keepBackup: true)
            }
        } message: {
            Text("This will backup /root directory before resetting. You can restore it later.")
        }
    }

    private var compactButton: some View {
        Menu {
            Button(action: { showResetAlert = true }) {
                Label("Reset All", systemImage: "trash")
            }

            if showBackupOption {
                Button(action: { showBackupAlert = true }) {
                    Label("Reset & Backup", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise.circle")
                .imageScale(.large)
                .foregroundStyle(CodyColors.statusErrorText)
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(Text("Reset Rootfs"))
    }

    private var normalButton: some View {
        Menu {
            Button(action: { showResetAlert = true }) {
                Label("Reset All", systemImage: "trash")
            }

            if showBackupOption {
                Button(action: { showBackupAlert = true }) {
                    Label("Reset & Backup", systemImage: "archivebox")
                }
            }
        } label: {
            Label("Reset Rootfs", systemImage: "arrow.clockwise")
                .font(CodyTypography.bodyLarge)
                .foregroundStyle(CodyColors.statusErrorText)
        }
        .buttonStyle(CodyPressableButtonStyle())
    }

    private var prominentButton: some View {
        VStack(spacing: CodySpacing.md) {
            Button(action: { showResetAlert = true }) {
                let shape = RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                Label("Reset Rootfs", systemImage: "arrow.clockwise")
                    .font(CodyTypography.labelLarge)
                    .padding(CodySpacing.lg)
                    .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard)
                    .foregroundStyle(CodyColors.statusErrorText)
                    .background(shape.fill(CodyColors.statusErrorBg))
                    .overlay {
                        shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
            }
            .buttonStyle(CodyPressableButtonStyle())

            if showBackupOption {
                Button(action: { showBackupAlert = true }) {
                    let shape = RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                    Label("Reset & Backup", systemImage: "archivebox")
                        .font(CodyTypography.labelLarge)
                        .padding(CodySpacing.lg)
                        .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard)
                        .foregroundStyle(CodyColors.statusWarningText)
                        .background(shape.fill(CodyColors.statusWarningBg))
                        .overlay {
                            shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(CodyPressableButtonStyle())
            }

            if isProcessing {
                HStack(spacing: CodySpacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage ?? "Processing...")
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                }
            }
        }
    }

    private func performReset(keepBackup: Bool) {
        isProcessing = true
        statusMessage = keepBackup ? "Backing up and resetting..." : "Resetting rootfs..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let backup = try RootfsManager.shared.reset(keepUserData: keepBackup)

                DispatchQueue.main.async {
                    self.isProcessing = false

                    if keepBackup, let backup = backup {
                        self.statusMessage = "✅ Reset complete. Backup at: \(backup.lastPathComponent)"
                    } else {
                        self.statusMessage = "✅ Reset complete. Restart app to reinstall."
                    }

                    // Clear message after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.statusMessage = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.statusMessage = "❌ Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// Quick access reset toolbar item
struct RootfsResetToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            RootfsResetButton(style: .compact)
        }
    }
}

// MARK: - Usage Examples

/*

 // Example 1: Add to toolbar
 .toolbar {
     RootfsResetToolbarItem()
 }

 // Example 2: Compact icon button
 RootfsResetButton(style: .compact)

 // Example 3: Normal button
 RootfsResetButton(style: .normal)

 // Example 4: Prominent styled buttons
 RootfsResetButton(style: .prominent)

 // Example 5: Reset only (no backup option)
 RootfsResetButton(style: .normal, showBackupOption: false)

 // Example 6: In a Form/List
 Section("Danger Zone") {
     RootfsResetButton(style: .normal)
 }

 // Example 7: Custom layout
 VStack {
     Text("System Management")
         .font(.headline)
     RootfsResetButton(style: .prominent)
 }

 */

#Preview("Compact") {
    NavigationStack {
        VStack {
            RootfsResetButton(style: .compact)
        }
        .navigationTitle("Compact Style")
    }
}

#Preview("Normal") {
    NavigationStack {
        List {
            Section("Actions") {
                RootfsResetButton(style: .normal)
            }
        }
        .navigationTitle("Normal Style")
    }
}

#Preview("Prominent") {
    NavigationStack {
        VStack(spacing: 20) {
            Text("Rootfs Management")
                .font(.title)
                .fontWeight(.bold)

            RootfsResetButton(style: .prominent)
        }
        .padding()
        .navigationTitle("Prominent Style")
    }
}
