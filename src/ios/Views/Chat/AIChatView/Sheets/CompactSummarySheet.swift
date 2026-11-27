//
//  CompactSummarySheet.swift
//  Cody - chat page (AIChatView)
//
//  CompactSummarySheet shows a compaction summary with an optional revert
//  action (opened from the message list); SelectableTextView renders the long
//  text with a UITextView.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI
import UIKit

// MARK: - Compact Summary Sheet

struct CompactSummarySheet: View {
    let summary: String
    /// Optional revert action. When provided, a "Revert Compact" button is shown
    /// below the summary; tapping it invokes the closure (typically wired to
    /// AIChatViewModel.revertCompact()) and dismisses the sheet.
    var onRevert: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var copied = false
    @State private var showRevertConfirm = false

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        NavigationStack {
            VStack(spacing: 0) {
                SelectableTextView(text: summary)
                    .padding(CodySpacing.lg)
                    .background(cardShape.fill(CodyColors.bgGroupedSurface))
                    .clipShape(cardShape)
                    .overlay {
                        cardShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .padding(CodySpacing.lg)

                if onRevert != nil {
                    VStack(spacing: 0) {
                        Button(role: .destructive) {
                            showRevertConfirm = true
                        } label: {
                            HStack(spacing: CodySpacing.xsPlus) {
                                Image(systemName: "arrow.uturn.backward")
                                    .accessibilityHidden(true)
                                Text("Revert Compact")
                            }
                            .font(CodyTypography.labelLarge)
                            .foregroundStyle(CodyColors.statusErrorText)
                            .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard)
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
                        .padding(.horizontal, CodySpacing.lg)
                        .padding(.vertical, CodySpacing.md)
                    }
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
            .navigationTitle("Compact Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CodyColors.iconSecondary)
                    }
                    .accessibilityLabel(AppLocalized("Close"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = summary
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .foregroundStyle(copied ? CodyColors.statusSuccessText : CodyColors.iconSecondary)
                    }
                    .accessibilityLabel(copied ? AppLocalized("Copied") : AppLocalized("Copy"))
                }
            }
            .alert("Revert this compact?", isPresented: $showRevertConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Revert", role: .destructive) {
                    let action = onRevert
                    dismiss()
                    action?()
                }
            } message: {
                Text("The summary will be discarded and the messages it covered will become active again. This may push the conversation past the model's context window — if that happens, long-press a message to re-compact from that point.")
            }
        }
        .presentationDetents([.large])
    }
}

/// UITextView wrapper for efficient rendering of long selectable text.
private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        // [T-ios-datadetector-hardening] DEFENSIVE ONLY — see the longer note
        // in SelectableMarkdownTextView.init. UITextView already defaults this
        // to [], so this changes no behavior today and does NOT address the
        // 1.14(8) DataDetectorsUI/Calculate watchdog hang (a system-framework
        // stall during edit-menu construction, no Cody frames). It states the
        // policy so a future SDK default cannot silently opt this view in.
        tv.dataDetectorTypes = []
        tv.font = .preferredFont(forTextStyle: .subheadline)
        tv.adjustsFontForContentSizeCategory = true
        tv.textColor = CodyUIColors.textPrimary
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.showsVerticalScrollIndicator = true
        tv.alwaysBounceVertical = true
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }
}
