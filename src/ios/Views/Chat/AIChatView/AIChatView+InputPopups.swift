//
//  AIChatView+InputPopups.swift
//  Cody - chat page (AIChatView)
//
//  AIChatView, composer popups: the slash-command and @-mention popups (fixed
//  band above the input bar), their rows, highlight and chrome, and the
//  attachment grid.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import AVFoundation
import AVKit
import Combine
import GameController
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

extension AIChatView {
    /// Single overlay containing whichever input popup is active (slash or
    /// `@`-mention). Kept in one overlay slot to avoid compounding SwiftUI
    /// generic types on the body, which previously caused a runtime
    /// type-metadata recursion crash.
    /// [T-slash-picker-constant-band] Fixed top reserve for the slash /
    /// mention popup. Dynamic Island + navbar + a comfortable visual
    /// gap below the title block. Using a constant beats reading
    /// `topSafeAreaInset` because that value reports the bare safe-area
    /// inset (status bar + Dynamic Island, ~59pt) and skips the
    /// principal-toolbar title — so any computation off it leaves the
    /// popup overlapping the title row. 260pt covers the worst case
    /// (iOS 18, 3-line custom titleView).
    private static let slashPickerTopReserve: CGFloat = 260
    private static let slashPickerBottomMargin: CGFloat = 16
    /// [T-slash-picker-fixed-height] Locked popup height: shows up to
    /// 4 rows, then scrolls. Row visual height ≈ 46pt (13pt title +
    /// 11pt subtitle + per-row vertical padding); +8pt accounts for
    /// the inner VStack's first/last cap. The popup is now strictly
    /// `slashPickerRowHeight * 4 + 8 = 192pt` regardless of how many
    /// commands match, so the band is predictable and rows beyond the
    /// 4th are reachable via the visible scrollbar.
    // 54pt covers the tallest standard slash row including the `/thinking`
    // entry — its inline ThinkingLevel picker pushes the row above the
    // 44pt minHeight baseline. Earlier 46pt + visible=4 → 192pt clipped
    // the 4th row's tail. ×4 + 8pt bottom breathing = 224pt.
    private static let slashPickerRowHeight: CGFloat = 54
    private static let slashPickerVisibleRows: Int = 4
    // + top/bottom list inset (popupRowInset each side), so the selection
    // pill on the first / last row keeps the same gap to the card edge as
    // it has on the sides.
    private static let slashPickerFixedHeight: CGFloat =
        slashPickerRowHeight * CGFloat(slashPickerVisibleRows) + popupRowInset * 2

    @ViewBuilder
    var inputPopupOverlay: some View {
        ZStack {
            if vm.showSlashMenu && !vm.filteredSlashCommands.isEmpty {
                popupOverlayContainer(onDismiss: { vm.dismissSlashMenu() }) {
                    slashCommandMenu
                }
            } else if vm.showMentionMenu {
                popupOverlayContainer(onDismiss: { vm.dismissMentionMenu() }) {
                    mentionMenu
                }
            }
        }
        .animation(inputPopupAnimation, value: vm.showSlashMenu)
        .animation(inputPopupAnimation, value: vm.showMentionMenu)
    }

    private var inputPopupAnimation: Animation? {
        CodyMotion.resolved(CodyMotion.quick, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// [T-ipad-inputbar-height-zero] Bounds of the window hosting the chat, in
    /// the same GLOBAL space `onGeometryChange(.global)` reports.
    ///
    /// `UIScreen.main.bounds` is NOT a valid stand-in: under Mac Catalyst and in
    /// iPad multitasking the app's window is a sub-rect of the screen, and the
    /// chat pane is further inset by the sidebar — so screen-relative math
    /// misjudges a perfectly on-screen composer as offscreen. Falls back to the
    /// screen when no key window is available (early layout / previews).
    func inputBarWindowBounds() -> CGRect {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return UIScreen.main.bounds }
        // SwiftUI's .global space is the window's own coordinate space, so the
        // window's bounds (origin .zero) — not its frame — is the right rect.
        return window.bounds
    }

    /// Shared transition modifier for the `/` and `@` popups. Layout (popup
    /// position relative to input bar top) is now driven by SwiftUI itself
    /// — popup sits as `.overlay(alignment: .bottom)` on a catcher view
    /// directly above the input bar, so the bottom edge of the popup is
    /// pinned to the input bar's top edge. No more `inputBarHeight` @State
    /// math, no more screen-bottom relative padding.
    ///
    /// What this container does:
    /// - Wraps `content()` with the slide-from-bottom + fade transition
    ///   so the popup shows / hides smoothly.
    /// - Sets `.frame(maxHeight: .infinity, alignment: .bottom)` so when
    ///   the catcher's frame is larger than the popup card, the card
    ///   stays bottom-aligned (matches input bar top).
    @ViewBuilder
    private func popupOverlayContainer<Content: View>(
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            // .compositingGroup() flattens the popup card (chrome + ScrollView
            // + rows) into a single rendering layer BEFORE the transition
            // applies. Without this, SwiftUI animates each child view
            // independently — the text rows often appear instantly at their
            // final position while the chrome background slides up behind
            // them ("text shows first, card catches up"). Forcing a single
            // compositing pass makes the whole card move/fade as one unit.
            .compositingGroup()
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
    }

    /// Slash command popup in the band above the composer.
    /// [T-slash-picker-scroll] Wrapped in ScrollView with a half-screen height
    /// cap so long command lists (skills + builtin actions) stay reachable
    /// even when their natural height would push the bottom rows behind the
    /// input bar / keyboard. Tap-outside dismiss lives in `inputPopupOverlay`.
    private var slashCommandMenu: some View {
        InputBarPopupChrome(maxContentWidth: maxContentWidth) {
            ScrollView {
                VStack(spacing: 0) {
                    let commands = vm.filteredSlashCommands
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                        let isSelected = index == vm.slashMenuSelectedIndex
                        // [T-slash-picker-section-divider] Hairline between
                        // builtin commands and user-installed Skills so the
                        // two groups are visually distinct. Fires when this
                        // row is the first skill row in the list.
                        if cmd.isSkill && index > 0 && !commands[index - 1].isSkill {
                            Divider()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                        }
                        if cmd.id == "thinking" {
                            let supported = vm.currentModelSupportsReasoning
                            SlashCommandRow(
                                cmd: cmd,
                                memoryEnabled: vm.memoryEnabled,
                                thinkingLevel: vm.currentThinkingLevel,
                                thinkingSupported: supported,
                                availableLevels: vm.availableThinkingLevels,
                                onSetThinkingLevel: supported ? { level in
                                    vm.setThinkingLevel(level)
                                } : nil,
                                onToggleThinking: supported ? {
                                    let newLevel: ThinkingLevel = vm.currentThinkingLevel.isEnabled ? .off : .medium
                                    vm.setThinkingLevel(newLevel)
                                    vm.dismissSlashMenu()
                                } : nil
                            )
                            .background(SlashMenuRowHighlight(isSelected: isSelected))
                        } else {
                            Button {
                                vm.executeSlashCommand(cmd)
                            } label: {
                                SlashCommandRow(
                                    cmd: cmd,
                                    memoryEnabled: vm.memoryEnabled
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SlashMenuButtonStyle(isSelected: isSelected))
                        }
                    }
                }
                // Equal inset on all four sides; slashPickerFixedHeight
                // reserves the top/bottom share.
                .padding(Self.popupRowInset)
            }
            .scrollIndicators(.visible)
            .frame(height: Self.slashPickerFixedHeight)
        }
    }

    /// `@` file-mention popup — mirrors slashCommandMenu styling.
    private var mentionMenu: some View {
        let rows = vm.filteredMentionEntries
        #if DEBUG
        let preview = rows.prefix(6).map { $0.basename }.joined(separator: ",")
        print("[MentionRender] mentionMenu body filter=\"\(vm.mentionFilter)\" rows.count=\(rows.count) first6=[\(preview)]")
        #endif
        return InputBarPopupChrome(maxContentWidth: maxContentWidth) {
            VStack(spacing: 0) {
                if rows.isEmpty {
                    // Lock empty-state height to slashPickerFixedHeight so
                    // the popup card stays the same size whether matches
                    // are present or not — otherwise it collapses to a
                    // single-line height and the visual top edge jumps
                    // toward the input bar, breaking position parity with
                    // the slash popup (which is always 4-rows tall).
                    VStack {
                        HStack(spacing: 8) {
                            if FileMentionIndex.shared.isScanning {
                                ProgressView().scaleEffect(0.7)
                            }
                            Text(FileMentionIndex.shared.isScanning
                                 ? AppLocalized("Scanning files…")
                                 : AppLocalized("No matching files"))
                                .font(CodyTypography.bodyMedium)
                                .foregroundStyle(CodyColors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        Spacer(minLength: 0)
                    }
                    .frame(height: Self.slashPickerFixedHeight)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                // The LazyVStack outer `.id(vm.mentionFilter)`
                                // forces a full re-create on every query change,
                                // which dodges any stale-row reuse pathology;
                                // inside, the per-row id can stay simple
                                // (positional index).
                                ForEach(Array(rows.enumerated()), id: \.offset) { index, entry in
                                    let isSelected = index == vm.mentionSelectedIndex
                                    Button {
                                        vm.selectMention(entry)
                                    } label: {
                                        MentionRow(entry: entry)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(SlashMenuButtonStyle(isSelected: isSelected))
                                    .id(index)
                                }
                            }
                            // Tag the LazyVStack with the current filter so
                            // SwiftUI throws away its layout state when the
                            // search query changes. Without this, the lazy
                            // stack sometimes reused stale body content keyed
                            // off the previous query (the `@codex showing
                            // mteam-hub` symptom).
                            .id(vm.mentionFilter)
                            .padding(Self.popupRowInset)
                        }
                        // [T-slash-picker-fixed-height] Match slash popup:
                        // exactly 4 rows tall, scrolls on overflow with the
                        // visible indicator above.
                        .scrollIndicators(.visible)
                        .frame(height: Self.slashPickerFixedHeight)
                        .onChange(of: vm.mentionSelectedIndex) { newIndex in
                            guard newIndex >= 0, newIndex < rows.count else { return }
                            withAnimation(inputPopupAnimation) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                    if FileMentionIndex.shared.isScanning {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.6)
                            Text("Scanning more locations…")
                                .font(CodyTypography.bodySmall)
                                .foregroundStyle(CodyColors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    /// Shared surface and horizontal alignment for both autocomplete lists.
    private struct InputBarPopupChrome<Content: View>: View {
        let maxContentWidth: CGFloat?
        @ViewBuilder let content: () -> Content

        var body: some View {
            content()
                .frame(maxWidth: .infinity)
                .modifier(CodySurfaceModifier(radius: CodyRadius.surface))
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, CodyMetrics.Composer.outerMarginH)
        }
    }


    /// A single row in the file-mention menu.
    private struct MentionRow: View {
        let entry: FileMentionEntry

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CodyColors.iconSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.basename)
                        .font(CodyTypography.labelLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                        .lineLimit(1)
                    Text(entry.displayPath)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(entry.mountName ?? entry.scope.displayLabel)
                    .font(CodyTypography.labelSmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, CodySpacing.xsPlus)
                    .padding(.vertical, CodySpacing.xxs)
                    .background(Capsule().fill(CodyColors.bgTertiary))
            }
            .padding(.horizontal, CodySpacing.md)
            .padding(.vertical, CodySpacing.sm)
        }

        private var iconName: String {
            if entry.isDirectory { return "folder" }
            switch entry.scope {
            case .workspace:   return "doc.text"
            case .attachments: return "paperclip"
            case .shared:      return "folder.badge.person.crop"
            case .skills:      return "sparkles"
            case .memory:      return "brain.head.profile"
            case .mount:       return "externaldrive"
            }
        }
    }

    /// Attachment grid extracted to help the Swift type-checker.
    @ViewBuilder
    var inputAttachmentGrid: some View {
        InputAttachmentGridView(
            attachments: vm.attachments,
            loadingVideoCount: vm.loadingVideoCount,
            onRemove: { attachment in vm.removeAttachment(attachment) },
            onMove: { fromID, toID in
                withAnimation(CodyMotion.resolved(CodyMotion.layout, reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
                    vm.moveAttachment(fromID: fromID, toID: toID)
                }
            }
        )
    }

    /// Shared focus and press feedback for autocomplete rows.
    private struct SlashMenuButtonStyle: ButtonStyle {
        let isSelected: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(SlashMenuRowHighlight(isSelected: isSelected, isPressed: configuration.isPressed))
        }
    }

    /// Row highlight shared by button rows and the non-button `/thinking` row.
    private struct SlashMenuRowHighlight: View {
        let isSelected: Bool
        var isPressed: Bool = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // Concentric with the card: inner radius = outer radius - inset,
            // so the gap stays even around the pill's corners too.
            let shape = RoundedRectangle(
                cornerRadius: CodyRadius.surface - AIChatView.popupRowInset,
                style: .continuous
            )
            shape.fill(fill)
                .overlay {
                    if isSelected {
                        // The elevated surface and selected fill share a dark-mode value.
                        shape.strokeBorder(CodyColors.borderHeavy, lineWidth: CodySpacing.px)
                    }
                }
                .allowsHitTesting(false)
                .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isSelected)
                .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isPressed)
        }

        private var fill: Color {
            if isSelected { return CodyColors.bgSecondary }
            if isPressed { return CodyColors.interactiveRowPress }
            return Color.clear
        }
    }

    /// Inset between the popup card edge and the row highlight pills, on all
    /// four sides (the top/bottom share is reserved in slashPickerFixedHeight).
    fileprivate static let popupRowInset = CodySpacing.xsPlus

    /// Single row in the slash command menu.
    private struct SlashCommandRow: View {
        let cmd: AIChatViewModel.SlashCommand
        let memoryEnabled: Bool
        var thinkingLevel: ThinkingLevel = .off
        var thinkingSupported: Bool = true
        var availableLevels: [ThinkingLevel] = ThinkingLevel.allCases
        var onSetThinkingLevel: ((ThinkingLevel) -> Void)?
        var onToggleThinking: (() -> Void)?

        var body: some View {
            HStack(spacing: 8) {
                // Label area — tap to toggle thinking on/off and dismiss
                HStack(spacing: 10) {
                    Group {
                        if cmd.id == "thinking" {
                            Image("ThinkingIcon")
                                .resizable()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: cmd.icon)
                                .font(.system(size: 15, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .foregroundStyle(thinkingIconColor)
                    .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        let isThinkingActive = cmd.id == "thinking" && thinkingLevel.isEnabled && thinkingSupported
                        let titleColor = isThinkingActive ? CodyCategoryTint.blue.color : CodyColors.textPrimary
                        let subtitleText = (cmd.id == "thinking" && !thinkingSupported)
                            ? AppLocalized("Not supported by current model")
                            : cmd.subtitle
                        let subtitleColor = CodyColors.textSecondary
                        // [T-slash-picker-product-rules] Title + subtitle
                        // each clamped to a single line. Long skill names
                        // and descriptions used to wrap and pump the row
                        // height past 60pt, which then snowballed into a
                        // multi-screen picker.
                        Text("/\(cmd.title.lowercased())")
                            .font(CodyTypography.labelLarge)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(subtitleText)
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .allowsHitTesting(cmd.id == "thinking")
                .onTapGesture { onToggleThinking?() }
                if cmd.id == "memory" {
                    // [T-ios-voiceover-labels] Status glyph, not a control:
                    // give it the on/off meaning in words instead of letting
                    // VoiceOver read "checkmark circle fill" / "slash circle".
                    Image(systemName: memoryEnabled ? "checkmark.circle.fill" : "slash.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(memoryEnabled ? CodyCategoryTint.green.color : CodyColors.iconSecondary)
                        .accessibilityLabel(Text(
                            memoryEnabled
                                ? AppLocalized("Memory on", comment: "VoiceOver label for the memory status icon when enabled")
                                : AppLocalized("Memory off", comment: "VoiceOver label for the memory status icon when disabled")
                        ))
                }
                if cmd.id == "thinking" && thinkingSupported {
                    thinkingLevelPicker
                }
            }
            .padding(.horizontal, CodySpacing.md)
            .padding(.vertical, CodyMetrics.Composer.paddingV)
            .frame(minHeight: CodyControlHeight.standard)
        }

        private var thinkingIconColor: Color {
            let active = cmd.id == "thinking" && thinkingSupported && thinkingLevel.isEnabled
            return active ? CodyCategoryTint.blue.color : CodyColors.iconSecondary
        }

        private var thinkingLevelPicker: some View {
            let maxAvailable = availableLevels.last
            let isClamped = thinkingLevel.isEnabled && maxAvailable != nil && thinkingLevel > (maxAvailable ?? thinkingLevel)

            return HStack(spacing: 2) {
                ForEach(availableLevels, id: \.self) { level in
                    let isExactMatch = thinkingLevel == level
                    let isClampedHighlight = isClamped && level == maxAvailable
                    let isHighlighted = isExactMatch || isClampedHighlight

                    HStack(spacing: 1) {
                        Text(level.displayName)
                            .font(isHighlighted ? CodyTypography.labelMedium : CodyTypography.bodySmall)
                            .lineLimit(1)
                        if isClampedHighlight {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .foregroundStyle(isClampedHighlight ? CodyColors.statusWarningText : (isHighlighted ? CodyColors.interactivePrimaryLabel : CodyColors.textSecondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: CodyRadius.sm, style: .continuous)
                            .fill(
                                isHighlighted
                                    ? (isClampedHighlight
                                        ? CodyColors.statusWarningBg
                                        : CodyColors.interactivePrimaryBg)
                                    : Color.clear
                            )
                            .shadow(color: isHighlighted ? Color.black.opacity(0.15) : .clear, radius: 1.5, x: 0, y: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSetThinkingLevel?(isHighlighted ? .off : level) }
                    .id(level)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
                    .fill(CodyColors.bgTertiary)
            )
        }
    }
}
