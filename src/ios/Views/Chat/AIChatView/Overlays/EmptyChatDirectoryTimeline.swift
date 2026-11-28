//
//  EmptyChatDirectoryTimeline.swift
//  Cody - chat page (AIChatView)
//
//  Onboarding shown in an empty New Chat: the /var/cody directory layout.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI

struct NovaChatGreeting: View {
    let onSelect: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var soul = SoulStore.cachedMetadata

    var body: some View {
        ViewThatFits(in: .vertical) {
            greeting
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                greeting
            }
        }
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            soul = SoulStore.cachedMetadata
        }
    }

    private var greeting: some View {
        VStack(spacing: CodySpacing.lg) {
            Group {
                if soul.icon.isEmpty {
                    CodyIconView(.sparkles, size: 28)
                        .foregroundStyle(CodyColors.iconPrimary)
                } else {
                    SoulIconView(icon: soul.icon, size: soul.iconIsImage ? 52 : 26, cornerRadius: 26)
                }
            }
            .frame(width: 52, height: 52)
            .background(Circle().fill(CodyColors.bgElevatedPrimary))
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(CodyColors.borderLight, lineWidth: 1) }
            .accessibilityHidden(true)

            VStack(spacing: CodySpacing.xs) {
                Text(AppLocalized("What can I help with?"))
                    .font(CodyTypography.headlineSmall)
                    .foregroundStyle(CodyColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !soul.name.isEmpty && soul.name != SoulMetadata.default.name {
                    Text(soul.name)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)

            Grid(horizontalSpacing: CodySpacing.sm, verticalSpacing: CodySpacing.sm) {
                if dynamicTypeSize.isAccessibilitySize {
                    GridRow { summarize }
                    GridRow { code }
                    GridRow { shell }
                    GridRow { brainstorm }
                } else {
                    GridRow {
                        summarize
                        code
                    }
                    GridRow {
                        shell
                        brainstorm
                    }
                }
            }
        }
        .padding(.vertical, CodySpacing.md)
    }

    private var summarize: some View {
        prompt("Summarize / Explain", icon: "doc.text",
               draft: AppLocalized("Summarize the main points and explain them in plain language."))
    }

    private var code: some View {
        prompt("Code & Debug", icon: "chevron.left.forwardslash.chevron.right",
               draft: AppLocalized("Help me debug this code. Explain the cause and suggest a fix."))
    }

    private var shell: some View {
        prompt("Run Shell Task", icon: "terminal",
               draft: AppLocalized("Help me run a shell command and interpret the output."))
    }

    private var brainstorm: some View {
        prompt("Brainstorm", icon: "sparkles",
               draft: AppLocalized("Help me brainstorm ideas and compare their trade-offs."))
    }

    private func prompt(_ title: LocalizedStringKey, icon: String, draft: String) -> some View {
        Button {
            onSelect(draft)
        } label: {
            HStack(spacing: CodySpacing.sm) {
                CodyIconView(systemName: icon, size: 20, fallbackWeight: .medium)
                    .foregroundStyle(CodyColors.iconSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(CodyTypography.labelMedium)
                    .foregroundStyle(CodyColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CodySpacing.md)
            .padding(.vertical, CodySpacing.sm)
            .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
                    .fill(CodyColors.bgElevatedPrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
                    .strokeBorder(CodyColors.borderLight, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous))
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}

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
