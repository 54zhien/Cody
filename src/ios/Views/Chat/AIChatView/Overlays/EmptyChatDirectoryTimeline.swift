//
//  EmptyChatDirectoryTimeline.swift
//  Cody - chat page (AIChatView)
//
//  Onboarding shown in an empty New Chat: the /var/cody directory layout.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI

// MARK: - Empty Chat Directory Timeline

/// Onboarding view rendered in the center of a New Chat (no messages yet).
/// Shows the per-session vs cross-session directory layout under
/// `/var/cody/` as a 2-column folder grid so the user understands what's
/// available before typing.
///
/// Source-of-truth for the descriptions: AIChatViewModel.swift system-prompt
/// directory listing (`Shared directory /var/cody/ ...`). Keep them aligned
/// when either side changes.
struct EmptyChatDirectoryTimeline: View {
    var onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CodySpacing.md) {
            HStack(spacing: CodySpacing.sm) {
                Image(systemName: "lightbulb")
                    .font(CodyTypography.labelMedium)
                    .foregroundStyle(CodyColors.iconSecondary)
                    .accessibilityHidden(true)
                Text("Workspace layout")
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }

            HStack(alignment: .top, spacing: CodySpacing.smPlus) {
                CodyListIconBadge(systemImage: "folder", tint: .neutral)
                Text("Each chat gets its own **workspace**, **attachments**, **offloads**, and **browser** folders — wiped when the session ends.")
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: CodySpacing.smPlus) {
                CodyListIconBadge(systemImage: "folder.fill", tint: .blue)
                Text("All chats share **shared**, **skills**, **memory**, and **mounts** — persistent across sessions.")
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(action: onBrowse) {
                    HStack(spacing: CodySpacing.xsPlus) {
                        Image(systemName: "folder")
                            .font(CodyTypography.labelSmall.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("Browse Chat Files")
                            .font(CodyTypography.labelMedium)
                    }
                    .foregroundStyle(CodyColors.textPrimary)
                    .padding(.horizontal, CodySpacing.md)
                    .frame(minHeight: CodyControlHeight.sm)
                    .background(Capsule().fill(CodyColors.interactiveSecondaryBg))
                    .overlay {
                        Capsule()
                            .strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(CodyPressableButtonStyle())
            }
            .padding(.top, CodySpacing.xxs)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .modifier(CodyAgentCardModifier())
        .fixedSize(horizontal: false, vertical: true)
    }
}
