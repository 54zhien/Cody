//
//  DeleteConfirmSheet.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  Confirmation sheet for deleting sessions, listing what will be removed
//  (DeleteInfo from ContentView+SessionActions).
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Delete Confirm Sheet

struct DeleteConfirmSheet: View {
    @Binding var info: ContentView.DeleteInfo?
    let isLoading: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading || info == nil {
                    VStack(spacing: CodySpacing.lg) {
                        Spacer()
                        VStack(alignment: .leading, spacing: CodySpacing.md) {
                            CodyShimmeringText("Calculating…")
                                .font(CodyTypography.titleSmall)
                            CodySkeletonView(height: CodySpacing.lg, cornerRadius: CodyRadius.sm)
                            CodySkeletonView(width: 180, height: CodySpacing.lg, cornerRadius: CodyRadius.sm)
                        }
                        .padding(CodySpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardShape.fill(CodyColors.bgGroupedSurface))
                        .overlay {
                            cardShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                .allowsHitTesting(false)
                        }
                        Spacer()
                    }
                    .padding(CodySpacing.lg)
                    let _ = print("[DELETE] DeleteConfirmSheet showing ProgressView. isLoading=\(isLoading), info is \(info == nil ? "nil" : "non-nil")")
                } else if let info {
                    let _ = print("[DELETE] DeleteConfirmSheet showing info. sessionCount=\(info.sessionCount)")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Sessions
                            infoRow(
                                title: "Sessions",
                                value: info.childCount > 0
                                    ? "\(info.sessionCount - info.childCount) session\(info.sessionCount - info.childCount == 1 ? "" : "s") + \(info.childCount) agent session\(info.childCount == 1 ? "" : "s") and all messages"
                                    : "\(info.sessionCount) session\(info.sessionCount == 1 ? "" : "s") and all messages"
                            )
                            .padding(CodySpacing.lg)

                            // Files
                            if info.totalFileCount > 0 {
                                CodyColors.separator.frame(height: CodySpacing.px)
                                VStack(alignment: .leading, spacing: CodySpacing.xsPlus) {
                                    Text("Associated Files")
                                        .font(CodyTypography.labelLarge)
                                        .foregroundStyle(CodyColors.textPrimary)
                                    ForEach(info.fileNames, id: \.self) { name in
                                        HStack(spacing: CodySpacing.xsPlus) {
                                            Image(systemName: "doc")
                                                .font(CodyTypography.bodySmall)
                                                .foregroundStyle(CodyColors.iconSecondary)
                                                .accessibilityHidden(true)
                                            Text(name)
                                                .font(CodyTypography.bodyMedium)
                                                .foregroundStyle(CodyColors.textSecondary)
                                        }
                                    }
                                    if info.totalFileCount > info.fileNames.count {
                                        Text("and \(info.totalFileCount - info.fileNames.count) more file\(info.totalFileCount - info.fileNames.count == 1 ? "" : "s")")
                                            .font(CodyTypography.bodySmall)
                                            .foregroundStyle(CodyColors.textTertiary)
                                    }
                                }
                                .padding(CodySpacing.lg)
                            }

                            CodyColors.separator.frame(height: CodySpacing.px)

                            // Storage
                            infoRow(title: "Releases Storage", value: info.formattedSize, monospacedDigits: true)
                                .padding(CodySpacing.lg)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardShape.fill(CodyColors.bgGroupedSurface))
                        .overlay {
                            cardShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                .allowsHitTesting(false)
                        }
                        .padding(CodySpacing.lg)
                    }

                    // Buttons
                    VStack(spacing: CodySpacing.smPlus) {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete (\(info.formattedSize))")
                                .font(CodyTypography.titleMedium)
                                .monospacedDigit()
                                .foregroundStyle(CodyColors.statusErrorText)
                                .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard)
                                .padding(.horizontal, CodySpacing.lg)
                                .background(
                                    RoundedRectangle(cornerRadius: CodyRadius.pill, style: .continuous)
                                        .fill(CodyColors.statusErrorBg)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: CodyRadius.pill, style: .continuous)
                                        .strokeBorder(CodyColors.statusErrorText.opacity(0.25), lineWidth: CodySpacing.px)
                                        .allowsHitTesting(false)
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(CodyPressableButtonStyle())

                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(CodyTypography.titleSmall)
                                .foregroundStyle(CodyColors.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard)
                                .padding(.horizontal, CodySpacing.lg)
                                .background(
                                    RoundedRectangle(cornerRadius: CodyRadius.pill, style: .continuous)
                                        .fill(CodyColors.interactiveSecondaryBg)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: CodyRadius.pill, style: .continuous)
                                        .strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                        .allowsHitTesting(false)
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                    }
                    .padding(.horizontal, CodySpacing.xl)
                    .padding(.vertical, CodySpacing.md)
                    .background {
                        if reduceTransparency {
                            CodyColors.bgGroupedSurface
                        } else {
                            Rectangle().fill(.bar)
                        }
                    }
                    .overlay(alignment: .top) {
                        CodyColors.separator.frame(height: CodySpacing.px)
                    }
                }
            }
            .background(CodyColors.bgGrouped)
            .navigationTitle("Confirm Deletion")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func infoRow(title: LocalizedStringKey, value: String, monospacedDigits: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            Text(title)
                .font(CodyTypography.labelLarge)
                .foregroundStyle(CodyColors.textPrimary)
            Group {
                if monospacedDigits {
                    Text(value).monospacedDigit()
                } else {
                    Text(value)
                }
            }
            .font(CodyTypography.bodyMedium)
            .foregroundStyle(CodyColors.textSecondary)
        }
    }
}
