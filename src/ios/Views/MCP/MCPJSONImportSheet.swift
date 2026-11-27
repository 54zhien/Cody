//
//  MCPJSONImportSheet.swift
//  CodyApp
//
//  Paste an MCP server config (Claude-Desktop mcpServers JSON or compatible
//  variants), preview the parsed servers, then commit. Mirrors the Skills
//  import UX.
//

import SwiftUI

struct MCPJSONImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared

    @State private var text: String = ""
    @State private var parsed: [MCPServerConfig] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(CodyTypography.code)
                        .foregroundStyle(CodyColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(CodyColors.bgGroupedSurface)
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: text) { _ in
                            parsed = []
                            errorMessage = nil
                        }
                        .codyGroupedRow()
                } header: {
                    Text(AppLocalized("Paste MCP JSON"))
                        .settingsSectionHeading()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(CodyColors.statusErrorText)
                            .codyGroupedRow()
                    }
                }

                if !parsed.isEmpty {
                    Section {
                        Text(String(format: AppLocalized("Found %d server(s)"), parsed.count))
                            .font(CodyTypography.labelLarge)
                            .foregroundStyle(CodyColors.textPrimary)
                            .codyGroupedRow()
                        ForEach(parsed) { server in
                            HStack(spacing: CodySpacing.md) {
                                CodySettingsIconBadge(
                                    systemImage: server.isSTDIO ? "terminal" : "globe",
                                    tint: server.isSTDIO ? .blue : .green
                                )
                                Text(server.id)
                                    .font(CodyTypography.bodyLarge)
                                    .foregroundStyle(CodyColors.textPrimary)
                                Spacer()
                                CodyStatusPill(
                                    localized: server.isSTDIO ? "STDIO" : "HTTP",
                                    tone: .neutral
                                )
                            }
                            .codyGroupedRow()
                        }
                    } header: {
                        Text(AppLocalized("Preview"))
                            .settingsSectionHeading()
                    }
                }
            }
            .codyGroupedFormCanvas()
            .navigationTitle(Text("Import JSON"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if parsed.isEmpty {
                        Button(AppLocalized("Parse")) { parse() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button(AppLocalized("Import")) { commit() }
                    }
                }
            }
        }
    }

    private func parse() {
        do {
            parsed = try store.parseImport(text)
            errorMessage = nil
        } catch {
            parsed = []
            errorMessage = error.localizedDescription
        }
    }

    private func commit() {
        store.commitImport(parsed)
        dismiss()
    }
}
