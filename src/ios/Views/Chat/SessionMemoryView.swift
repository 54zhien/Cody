//
//  SessionMemoryView.swift
//  CodyApp
//
//  Shows all memory used in the current session: auto-injected + tool-recalled.
//

import SwiftUI

struct SessionMemoryView: View {
    @ObservedObject var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Section 1: Auto-injected memories
                Section {
                    ForEach(autoInjected, id: \.name) { item in
                        NavigationLink {
                            MemoryContentView(title: item.name, content: item.content, fileURL: item.fileURL)
                        } label: {
                            row(name: item.name, detail: item.detail, icon: item.icon, tint: .purple)
                        }
                        .codyGroupedRow()
                    }
                } header: {
                    Text("Auto-injected")
                        .settingsSectionHeading()
                } footer: {
                    Text("Loaded into system prompt at the start of each agent turn.")
                        .settingsSectionFooter()
                }

                // Section 2: Tool-recalled memories
                if !toolMemories.isEmpty {
                    Section {
                        ForEach(toolMemories) { item in
                            NavigationLink {
                                if item.isWrite {
                                    MemoryWriteDetailView(item: item)
                                } else {
                                    MemoryGetDetailView(item: item)
                                }
                            } label: {
                                row(
                                    name: item.title,
                                    detail: item.detail,
                                    icon: item.isWrite ? "square.and.pencil" : "magnifyingglass",
                                    tint: item.isWrite ? .orange : .blue
                                )
                            }
                            .codyGroupedRow()
                        }
                    } header: {
                        Text("Tool Activity")
                            .settingsSectionHeading()
                    } footer: {
                        Text("Memory reads and writes performed by the agent during this session.")
                            .settingsSectionFooter()
                    }
                }
            }
            .codyGroupedListCanvas()
            .navigationTitle("Memories in Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Row

    private func row(name: String, detail: String, icon: String, tint: CodyCategoryTint = .red) -> some View {
        HStack(spacing: CodySpacing.md) {
            CodySettingsIconBadge(systemImage: icon, tint: tint)
            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(name)
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, CodySpacing.xxs)
    }

    // MARK: - Auto-injected

    private struct AutoItem {
        let name: String
        let detail: String
        let icon: String
        let content: String
        let fileURL: URL?
    }

    private var autoInjected: [AutoItem] {
        var items: [AutoItem] = []
        let fm = FileManager.default
        let memDir = AIChatViewModel.codyMemoryPersistentDir

        // SOUL.md — listed first because it's the identity/personality
        // layer that SystemPromptBuilder.identitySection() injects at
        // the very top of every turn's system prompt. The Memory Sheet
        // previously only surfaced GLOBAL.md + daily logs, so users had
        // no way to confirm SOUL.md was reaching the model.
        let soulURL = memDir.appendingPathComponent("SOUL.md")
        if fm.fileExists(atPath: soulURL.path),
           let content = try? String(contentsOf: soulURL, encoding: .utf8),
           !content.isEmpty {
            let lineCount = content.components(separatedBy: "\n").count
            items.append(AutoItem(
                name: "SOUL.md",
                detail: "\(lineCount) lines (full)",
                icon: "person.fill",
                content: content,
                fileURL: soulURL
            ))
        } else {
            items.append(AutoItem(name: "SOUL.md", detail: "Empty", icon: "person", content: "(empty)", fileURL: soulURL))
        }

        // GLOBAL.md
        let globalURL = memDir.appendingPathComponent("GLOBAL.md")
        if fm.fileExists(atPath: globalURL.path),
           let content = try? String(contentsOf: globalURL, encoding: .utf8),
           !content.isEmpty {
            let lineCount = content.components(separatedBy: "\n").count
            items.append(AutoItem(
                name: "GLOBAL.md",
                detail: "\(lineCount) lines (full)",
                icon: "star.fill",
                content: content,
                fileURL: globalURL
            ))
        } else {
            items.append(AutoItem(name: "GLOBAL.md", detail: "Empty", icon: "star", content: "(empty)", fileURL: globalURL))
        }

        // Most recent 3 daily logs with content (matches system prompt injection logic)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let today = Date()
        var found = 0
        var dayOffset = 0
        let maxLookback = 30

        while found < 3 && dayOffset < maxLookback {
            let date = today.addingTimeInterval(-Double(dayOffset) * 86400)
            let dateStr = dateFmt.string(from: date)
            let fileName = "\(dateStr).md"
            let fileURL = memDir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: fileURL.path),
               let content = try? String(contentsOf: fileURL, encoding: .utf8),
               !content.isEmpty {
                let lineCount = content.components(separatedBy: "\n").count
                let injected = min(lineCount, 200)
                let detail = lineCount > 200
                    ? "\(injected)/\(lineCount) lines injected"
                    : "\(lineCount) lines (full)"
                let label: String
                switch dayOffset {
                case 0: label = AppLocalized("Today")
                case 1: label = AppLocalized("Yesterday")
                default: label = dateStr
                }
                items.append(AutoItem(
                    name: "\(label) — \(fileName)",
                    detail: detail,
                    icon: "calendar",
                    content: content,
                    fileURL: fileURL
                ))
                found += 1
            }
            dayOffset += 1
        }

        return items
    }

    // MARK: - Tool memories

    struct ToolMemoryItem: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        /// The tool result output (what the tool returned to the agent).
        let content: String
        let isWrite: Bool
        /// The original content written by memory_write, parsed from toolInputArgs.
        let writtenContent: String?
        /// Keywords used for memory_get search.
        let keywords: String?
    }

    private var toolMemories: [ToolMemoryItem] {
        var items: [ToolMemoryItem] = []
        for message in vm.messages {
            for block in message.blocks {
                guard case .memoryTool(let action) = block.kind else { continue }
                let isWrite = action == "memory_write"
                let summary = block.toolSummary ?? action

                var writtenContent: String?
                var keywords: String?

                if let argsJson = block.toolInputArgs,
                   let data = argsJson.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if isWrite {
                        writtenContent = dict["content"] as? String
                    } else {
                        keywords = dict["keywords"] as? String
                    }
                }

                // Build a meaningful detail preview
                let detail: String
                if isWrite, let written = writtenContent {
                    // Show what was written
                    let firstLine = written.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? ""
                    detail = String(firstLine.prefix(100))
                } else if !isWrite {
                    // Show keywords + result summary
                    let resultLines = block.content.components(separatedBy: "\n").filter { !$0.isEmpty }
                    if let kw = keywords, !kw.isEmpty {
                        let matchCount = resultLines.filter { $0.hasPrefix("---") || $0.hasPrefix("## ") }.count
                        detail = "Search: \(kw)" + (matchCount > 0 ? " (\(matchCount) files)" : "")
                    } else {
                        detail = String((resultLines.first ?? "").prefix(100))
                    }
                } else {
                    detail = String(block.content.prefix(100))
                }

                items.append(ToolMemoryItem(
                    title: summary,
                    detail: detail,
                    content: block.content,
                    isWrite: isWrite,
                    writtenContent: writtenContent,
                    keywords: keywords
                ))
            }
        }
        return items
    }
}

// MARK: - Content Detail

private struct MemoryContentView: View {
    let title: String
    let content: String
    let fileURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editedContent: String = ""
    @State private var isEditing = false
    @State private var saved = false

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(CodyTypography.code)
                    .foregroundStyle(CodyColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(CodyColors.bgGroupedSurface)
                    .padding(.horizontal, CodySpacing.sm)
            } else {
                ScrollView {
                    Text(content)
                        .font(CodyTypography.code)
                        .foregroundStyle(CodyColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CodySpacing.lg)
                        .textSelection(.enabled)
                }
            }
        }
        .background(CodyColors.bgGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if fileURL != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            save()
                        }
                    } else {
                        Button {
                            editedContent = content
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(Text("Edit"))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if saved {
                Text("Saved")
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.vertical, CodySpacing.smPlus)
                    .background(CodyColors.interactivePrimaryBg, in: Capsule())
                    .padding(.bottom, CodySpacing.lg)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            try editedContent.write(to: url, atomically: true, encoding: .utf8)
            // SOUL.md needs the same side effects SoulStore.save() does:
            // refresh the in-memory metadata cache (so the chat header /
            // SystemPromptBuilder pick up the new identity) and mark it
            // dirty for iCloud sync. Without these, edits in this sheet
            // would land on disk but the running app + peer devices
            // would keep using the stale identity until next launch.
            if url.lastPathComponent == "SOUL.md" {
                SoulStore.refreshCache()
                Task { await ChatStore.shared.markDirty(recordType: "SoulV2", recordId: "soul") }
            }
            isEditing = false
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { saved = false }
            }
        } catch {
            // stay in editing mode on failure
        }
    }
}

// MARK: - Memory Write Detail (with revoke)

private struct MemoryWriteDetailView: View {
    let item: SessionMemoryView.ToolMemoryItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    @State private var editedContent: String = ""
    @State private var showRevokeAlert = false
    @State private var revokeResult: String?
    @State private var showResultAlert = false
    @State private var saved = false

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(CodyTypography.code)
                    .foregroundStyle(CodyColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(CodyColors.bgGroupedSurface)
                    .padding(.horizontal, CodySpacing.sm)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: CodySpacing.md) {
                        if let written = item.writtenContent {
                            SectionHeader(title: "Written Content")
                            Text(written)
                                .font(CodyTypography.code)
                                .foregroundStyle(CodyColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(CodySpacing.md)
                                .modifier(CodySurfaceModifier(radius: CodyRadius.surface))
                                .padding(.horizontal, CodySpacing.lg)
                                .textSelection(.enabled)
                        }

                        SectionHeader(title: "Tool Result")
                        Text(item.content)
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(CodySpacing.md)
                            .modifier(CodySurfaceModifier(radius: CodyRadius.surface))
                            .padding(.horizontal, CodySpacing.lg)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, CodySpacing.md)
                }
            }
        }
        .background(CodyColors.bgGrouped)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") { saveEdit() }
                } else {
                    if item.writtenContent != nil {
                        Button {
                            editedContent = item.writtenContent ?? ""
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(Text("Edit"))
                    }
                    Button {
                        showRevokeAlert = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(item.writtenContent == nil)
                    .accessibilityLabel(Text("Revoke"))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if saved {
                Text("Saved")
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.vertical, CodySpacing.smPlus)
                    .background(CodyColors.interactivePrimaryBg, in: Capsule())
                    .padding(.bottom, CodySpacing.lg)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Revoke Memory", isPresented: $showRevokeAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                revokeResult = revokeEntry()
                showResultAlert = true
            }
        } message: {
            Text("Remove this memory entry from the daily log? This cannot be undone.")
        }
        .alert(revokeResult ?? "", isPresented: $showResultAlert) {
            Button("OK") {
                if revokeResult?.hasPrefix("Removed") == true {
                    dismiss()
                }
            }
        }
    }

    private func saveEdit() {
        guard let written = item.writtenContent else { return }
        let result = replaceEntryInLog(oldContent: written, newContent: editedContent)
        if result != nil {
            isEditing = false
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { saved = false }
            }
        }
    }

    /// Find entry matching `oldContent` in daily logs and replace its body with `newContent`.
    /// Returns the filename on success, nil on failure.
    private func replaceEntryInLog(oldContent: String, newContent: String) -> String? {
        let fm = FileManager.default
        let memDir = AIChatViewModel.codyMemoryPersistentDir
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let candidates = [
            dateFmt.string(from: Date()),
            dateFmt.string(from: Date().addingTimeInterval(-86400))
        ]

        for dateStr in candidates {
            let fileURL = memDir.appendingPathComponent("\(dateStr).md")
            guard fm.fileExists(atPath: fileURL.path),
                  let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            let pattern = "<!-- \\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} -->\n"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let nsContent = fileContent as NSString
            let matches = regex.matches(in: fileContent, range: NSRange(location: 0, length: nsContent.length))

            for (i, match) in matches.enumerated() {
                let contentStart = match.range.location + match.range.length
                let entryEnd: Int
                if i + 1 < matches.count {
                    entryEnd = matches[i + 1].range.location
                } else {
                    entryEnd = nsContent.length
                }

                let bodyRange = NSRange(location: contentStart, length: entryEnd - contentStart)
                let body = nsContent.substring(with: bodyRange)
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedOld = oldContent.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmedBody == trimmedOld {
                    let replacement = newContent.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                    let newFileContent = nsContent.replacingCharacters(in: bodyRange, with: replacement)
                    if let _ = try? newFileContent.write(to: fileURL, atomically: true, encoding: .utf8) {
                        return dateStr
                    }
                }
            }
        }
        return nil
    }

    /// [T-ios-memory-write-revoke] Delegates to the shared revoker, which the
    /// tool capsule's long-press menu uses too — the entry-deletion logic must
    /// not drift between the two entry points.
    private func revokeEntry() -> String {
        guard let written = item.writtenContent else {
            return AppLocalized("No written content to revoke.")
        }
        return MemoryWriteRevoker.revoke(writtenContent: written)
    }
}

// MARK: - Memory Get Detail

private struct MemoryGetDetailView: View {
    let item: SessionMemoryView.ToolMemoryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodySpacing.md) {
                if let kw = item.keywords, !kw.isEmpty {
                    HStack(spacing: CodySpacing.xsPlus) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(CodyColors.iconSecondary)
                            .accessibilityHidden(true)
                        Text(kw)
                            .font(CodyTypography.labelLarge)
                            .foregroundStyle(CodyColors.textPrimary)
                    }
                    .padding(.horizontal, CodySpacing.md)
                    .padding(.vertical, CodySpacing.sm)
                    .modifier(CodySurfaceModifier(radius: CodyRadius.control))
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.top, CodySpacing.sm)
                }

                Text(item.content)
                    .font(CodyTypography.code)
                    .foregroundStyle(CodyColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CodySpacing.md)
                    .modifier(CodySurfaceModifier(radius: CodyRadius.surface))
                    .padding(.horizontal, CodySpacing.lg)
                    .textSelection(.enabled)
            }
            .padding(.bottom, CodySpacing.lg)
        }
        .background(CodyColors.bgGrouped)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(CodyTypography.sectionHeader)
            .foregroundStyle(CodyColors.textSecondary)
            .padding(.horizontal, CodySpacing.lg)
            .accessibilityAddTraits(.isHeader)
    }
}
