//
//  ExportPreviewSheet.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  Export result: ExportSummary and the preview sheet, with the share sheet
//  and document picker it presents (private to this file).
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI
import UIKit

// MARK: - Export Summary

struct ExportSummary {
    var format: String = ""
    var sessionCount: Int = 0
    var totalMessages: Int = 0
    var attachmentCount: Int = 0
    var earliest: Date? = nil
    var latest: Date? = nil
    var fileSizeBytes: Int64 = 0
}

// MARK: - Export Preview Sheet

struct ExportPreviewSheet: View {
    /// The artifact the user shares / saves — normally a `.zip`.
    let fileURL: URL?
    /// [T-export-preview-blank] The text payload to RENDER. Distinct from
    /// `fileURL` because the shared artifact is zipped, and zip bytes never
    /// decode as UTF-8 — reading `fileURL` left the pane blank while the file
    /// size (read from filesystem attributes, not the content) still showed,
    /// which is exactly how the bug presented. Falls back to `fileURL` when the
    /// caller has nothing separate to offer.
    var previewURL: URL? = nil
    let summary: ExportSummary?

    /// File to read for the on-screen text.
    private var textSourceURL: URL? { previewURL ?? fileURL }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showShareSheet = false
    @State private var showFilePicker = false
    @State private var copied = false
    @State private var previewText: String = ""
    @State private var fileSize: String = ""
    @State private var isLoadingPreview = true

    private let previewLimit = 10000

    var body: some View {
        let blockShape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        NavigationStack {
            VStack(spacing: 0) {
                // Preview — summary for multi-select, full content for single.
                if let summary {
                    summaryView(summary)
                } else if isLoadingPreview {
                    VStack {
                        VStack(alignment: .leading, spacing: CodySpacing.smPlus) {
                            CodySkeletonView(height: CodySpacing.mdPlus, cornerRadius: CodyRadius.sm)
                            CodySkeletonView(width: 240, height: CodySpacing.mdPlus, cornerRadius: CodyRadius.sm)
                            CodySkeletonView(width: 280, height: CodySpacing.mdPlus, cornerRadius: CodyRadius.sm)
                            CodySkeletonView(width: 190, height: CodySpacing.mdPlus, cornerRadius: CodyRadius.sm)
                        }
                        .padding(CodySpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(blockShape.fill(CodyColors.bgCodeBlock))
                        .overlay {
                            blockShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                .allowsHitTesting(false)
                        }
                        .padding(CodySpacing.lg)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        Text(previewText)
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(CodySpacing.lg)
                            .textSelection(.enabled)
                    }
                    .background(blockShape.fill(CodyColors.bgCodeBlock))
                    .clipShape(blockShape)
                    .overlay {
                        blockShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .padding(CodySpacing.lg)
                }

                VStack(spacing: CodySpacing.xsPlus) {
                    // File size info
                    if !fileSize.isEmpty {
                        Text(fileSize)
                            .font(CodyTypography.labelSmall.monospacedDigit())
                            .foregroundStyle(CodyColors.textTertiary)
                    }

                    // Action buttons
                    HStack(spacing: CodySpacing.sm) {
                        // [T-export-preview-blank] Copy needs a TEXT source. It used to
                        // test `fileURL`, which is the zip, so Copy silently vanished
                        // from every single-session export — the same zip-vs-payload
                        // confusion that blanked the preview. Test the payload we
                        // actually read instead, so Copy is offered exactly when there
                        // is something readable to copy.
                        if summary == nil, textSourceURL?.pathExtension.lowercased() != "zip" {
                            actionButton(
                                icon: copied ? "checkmark" : "doc.on.doc",
                                label: copied ? AppLocalized("Copied") : AppLocalized("Copy"),
                                tint: copied ? CodyColors.statusSuccessText : CodyColors.textPrimary
                            ) {
                                if let url = textSourceURL, let content = try? String(contentsOf: url, encoding: .utf8) {
                                    UIPasteboard.general.string = content
                                }
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            }
                        }
                        actionButton(icon: "square.and.arrow.up", label: AppLocalized("Share")) {
                            showShareSheet = true
                        }
                        actionButton(icon: "folder", label: AppLocalized("Save to Files")) {
                            showFilePicker = true
                        }
                    }
                    .padding(.horizontal, CodySpacing.lg)
                }
                .padding(.top, CodySpacing.smPlus)
                .padding(.bottom, CodySpacing.md)
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
            .background(CodyColors.bgGrouped)
            .navigationTitle(AppLocalized("Export Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Done")) { dismiss() }
                        .font(CodyTypography.labelLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = fileURL {
                    ShareSheet(url: url)
                }
            }
            .sheet(isPresented: $showFilePicker) {
                if let url = fileURL {
                    DocumentExportPicker(url: url)
                }
            }
            .task {
                if summary == nil {
                    await loadPreview()
                } else {
                    // Still compute file size for the action bar.
                    if let url = fileURL,
                       let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? Int64 {
                        let formatter = ByteCountFormatter()
                        formatter.countStyle = .file
                        fileSize = formatter.string(fromByteCount: size)
                    }
                    isLoadingPreview = false
                }
            }
        }
    }

    @ViewBuilder
    private func summaryView(_ s: ExportSummary) -> some View {
        let dateFmt: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()
        let sizeStr: String = {
            let f = ByteCountFormatter()
            f.countStyle = .file
            return f.string(fromByteCount: s.fileSizeBytes)
        }()
        let timeRange: String = {
            guard let e = s.earliest, let l = s.latest else { return "—" }
            return "\(dateFmt.string(from: e)) ~ \(dateFmt.string(from: l))"
        }()

        let cardShape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryRow(AppLocalized("Format"), s.format)
                CodyColors.separator.frame(height: CodySpacing.px)
                summaryRow(AppLocalized("Sessions"), "\(s.sessionCount)")
                CodyColors.separator.frame(height: CodySpacing.px)
                summaryRow(AppLocalized("Messages"), "\(s.totalMessages)")
                CodyColors.separator.frame(height: CodySpacing.px)
                summaryRow(AppLocalized("Time range"), timeRange)
                CodyColors.separator.frame(height: CodySpacing.px)
                summaryRow(AppLocalized("Attachments"), "\(s.attachmentCount)")
                CodyColors.separator.frame(height: CodySpacing.px)
                summaryRow(AppLocalized("Estimated size"), sizeStr)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(CodyColors.bgGroupedSurface))
            .overlay {
                cardShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .padding(CodySpacing.lg)
        }
    }

    private func summaryRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CodySpacing.md) {
            Text(key)
                .font(CodyTypography.bodyMedium)
                .foregroundStyle(CodyColors.textSecondary)
            Spacer(minLength: CodySpacing.md)
            Text(value)
                .font(CodyTypography.bodyMedium.monospacedDigit())
                .foregroundStyle(CodyColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, CodySpacing.lg)
        .padding(.vertical, CodySpacing.md)
    }

    private func loadPreview() async {
        guard let url = textSourceURL else {
            isLoadingPreview = false
            return
        }

        // Load file size — of the SHARED artifact (`fileURL`), not the preview
        // payload. The number under the pane labels the file the user is about to
        // share or save, so it has to be the zip's size even though the text above
        // it comes from the uncompressed payload.
        if let sizeURL = fileURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: sizeURL.path),
           let size = attrs[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            fileSize = formatter.string(fromByteCount: size)
        }

        // Read only the preview portion to avoid loading huge files into memory
        await Task.detached(priority: .utility) {
            var preview = ""
            if let handle = FileHandle(forReadingAtPath: url.path) {
                // Read at most previewLimit bytes worth of data
                let data = handle.readData(ofLength: previewLimit * 4) // UTF-8 can be up to 4 bytes per char
                handle.closeFile()
                // [T-export-preview-blank] Decode defensively. `readData` cuts at a
                // byte offset, so on any file larger than the read window the cut
                // can land mid-UTF-8-sequence and strict decoding returns nil —
                // another silent blank page, this time only for big exports.
                // Retry by trimming up to 3 trailing bytes (the longest possible
                // partial sequence), then fall back to a lossy decode so the user
                // sees the content rather than nothing.
                var decoded = String(data: data, encoding: .utf8)
                if decoded == nil, data.count > 3 {
                    for drop in 1...3 {
                        if let t = String(data: data.dropLast(drop), encoding: .utf8) {
                            decoded = t
                            break
                        }
                    }
                }
                let text = decoded ?? String(decoding: data, as: UTF8.self)
                if !text.isEmpty {
                    if text.count > previewLimit {
                        preview = String(text.prefix(previewLimit)) + "\n\n…"
                    } else {
                        preview = text
                    }
                }
            }
            await MainActor.run {
                previewText = preview
                isLoadingPreview = false
            }
        }.value
    }

    private func actionButton(icon: String, label: String, tint: Color = CodyColors.textPrimary, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
        return Button(action: action) {
            VStack(spacing: CodySpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .accessibilityHidden(true)
                Text(label)
                    .font(CodyTypography.labelSmall)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: CodyControlHeight.lg)
            .padding(.horizontal, CodySpacing.sm)
            .background(shape.fill(CodyColors.interactiveSecondaryBg))
            .overlay {
                shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // [T-share-sheet-uti] Defense against ShareKit's
        // UTTypeGetForIdentifier assert on Mac Catalyst — see
        // CodyShareSheet.sanitizedShareURL for context.
        let safeURL = CodyShareSheet.sanitizedShareURL(url) ?? url
        return UIActivityViewController(activityItems: [safeURL], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Document Export Picker

private struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url])
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
}
