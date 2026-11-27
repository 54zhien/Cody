//
//  SessionMCPsView.swift
//  CodyApp
//
//  Per-session MCP-server toggle sheet: override which MCP servers are active
//  in a chat. Mirrors SessionSkillsView.
//

import SwiftUI

struct SessionMCPsView: View {
    /// The real session id, or nil for a draft chat that hasn't sent its first
    /// message yet. Never coerced to "" (T-ios-session-skill-override-init-timing).
    let sessionId: String?
    /// Materializes the draft into a real session and returns its id; called
    /// lazily on first toggle. Mirrors SessionModelPicker / SessionSkillsView.
    var ensureSessionId: (() async -> String)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MCPStore.shared
    @State private var searchQuery = ""
    /// Id reads/writes resolve against; seeded from `sessionId`, upgraded to the
    /// real id once a draft is materialized on first toggle.
    @State private var resolvedSessionId: String?

    init(sessionId: String?, ensureSessionId: (() async -> String)? = nil) {
        self.sessionId = sessionId
        self.ensureSessionId = ensureSessionId
        _resolvedSessionId = State(initialValue: sessionId)
    }

    /// Whether `server` is enabled for this session. With no resolved session
    /// (draft) reads the server's GLOBAL default so the sheet shows correct state.
    private func isEnabled(_ server: MCPServerConfig) -> Bool {
        if let sid = resolvedSessionId {
            return store.isEnabledForSession(server.id, sessionId: sid)
        }
        return server.enabled
    }

    /// Apply a toggle: materialize the draft session if needed, then write the
    /// override against the real id.
    private func setOverride(_ server: MCPServerConfig, _ enabled: Bool) {
        if let sid = resolvedSessionId {
            store.setSessionOverride(serverId: server.id, sessionId: sid, enabled: enabled)
            return
        }
        Task {
            guard let sid = await ensureSessionId?() else { return }
            await MainActor.run {
                resolvedSessionId = sid
                store.setSessionOverride(serverId: server.id, sessionId: sid, enabled: enabled)
            }
        }
    }

    /// Enable/Disable All: materialize the draft session ONCE, then write each.
    private func applyToAll(_ scope: [MCPServerConfig], enabled: Bool) {
        if let sid = resolvedSessionId {
            for server in scope {
                store.setSessionOverride(serverId: server.id, sessionId: sid, enabled: enabled)
            }
            return
        }
        Task {
            guard let sid = await ensureSessionId?() else { return }
            await MainActor.run {
                resolvedSessionId = sid
                for server in scope {
                    store.setSessionOverride(serverId: server.id, sessionId: sid, enabled: enabled)
                }
            }
        }
    }

    private var filteredServers: [MCPServerConfig] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.servers }
        return store.servers.filter {
            $0.id.lowercased().contains(q) || ($0.note ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        // Reference the version counter so SwiftUI refreshes on override changes.
        let _ = store.sessionOverrideVersion

        NavigationStack {
            List {
                if store.servers.isEmpty {
                    Section {
                        SessionOverrideEmptyCard(systemImage: "square.stack.3d.up",
                                                 title: AppLocalized("No MCP servers"),
                                                 subtitle: AppLocalized("Add servers in Settings → MCP Integrations."))
                            .codyGroupedRow()
                    }
                } else if filteredServers.isEmpty {
                    Section {
                        Text(AppLocalized("No MCP servers match \"\(searchQuery)\"."))
                            .foregroundStyle(CodyColors.textSecondary)
                            .font(CodyTypography.bodyMedium)
                            .codyGroupedRow()
                    }
                } else {
                    Section {
                        ForEach(filteredServers) { server in
                            // [T-session-mcp-detail] A tap opens the read-only
                            // detail; the toggle keeps its own tap target.
                            NavigationLink {
                                SessionMCPDetailView(server: server)
                            } label: {
                                HStack(spacing: CodySpacing.md) {
                                    CodySettingsIconBadge(
                                        systemImage: server.isSTDIO ? "terminal" : "globe",
                                        tint: isEnabled(server) ? .blue : .neutral
                                    )
                                    VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                                        Text(server.id)
                                            .font(CodyTypography.bodyLarge)
                                            .foregroundStyle(CodyColors.textPrimary)
                                        if let note = server.note, !note.isEmpty {
                                            Text(note)
                                                .font(CodyTypography.bodySmall)
                                                .foregroundStyle(CodyColors.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { isEnabled(server) },
                                        set: { setOverride(server, $0) }
                                    ))
                                    .labelsHidden()
                                }
                                .padding(.vertical, CodySpacing.xxs)
                            }
                            .codyGroupedRow()
                        }
                    } header: {
                        let scope = filteredServers
                        SessionBulkToggleHeader(
                            availability: SessionBulkToggleRules.availability(scope.map { isEnabled($0) })
                        ) { applyToAll(scope, enabled: $0) }
                    } footer: {
                        SessionOverrideListFooter(
                            note: Text("Toggles override the server's default for this session only."),
                            searchQuery: searchQuery)
                            .settingsSectionFooter()
                    }
                }
            }
            .codyGroupedListCanvas()
            .navigationTitle("MCPs in Session")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(AppLocalized("Search MCP servers")))
            .onAppear { store.load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// BEGIN MCPServerDetailRules
/// What the read-only server detail shows, kept free of SwiftUI for tests.
enum MCPServerDetailRules {
    /// The config does not record whether a URL server speaks Streamable HTTP
    /// or SSE, so a URL server is shown as both, like the Android sheet.
    static func transportLabel(isSTDIO: Bool) -> String {
        isSTDIO ? "STDIO" : "HTTP / SSE"
    }

    /// Header / env-var NAMES, sorted. Only the keys are read: the values
    /// routinely hold API keys and this sheet sits over a chat that may be
    /// screen-shared, so they never reach the UI.
    static func secretNames(_ map: [String: String]?) -> [String] {
        guard let map else { return [] }
        return map.keys.sorted()
    }

    /// Args joined for display, or nil when there are none.
    static func argsLine(_ args: [String]?) -> String? {
        guard let args, !args.isEmpty else { return nil }
        return args.joined(separator: " ")
    }

    static func trimmedNote(_ note: String?) -> String? {
        let t = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
// END MCPServerDetailRules

/// [T-session-mcp-detail] Read-only detail of one MCP server, opened from the
/// in-chat sheet (Android 3109967bc has the same page). Nothing here writes
/// the config, exports it, or reads a header / env value.
private struct SessionMCPDetailView: View {
    let server: MCPServerConfig
    @State private var authorized = false

    var body: some View {
        let headerNames = MCPServerDetailRules.secretNames(server.headers)
        let envNames = MCPServerDetailRules.secretNames(server.env)
        List {
            Section {
                LabeledContent(AppLocalized("Transport"),
                               value: MCPServerDetailRules.transportLabel(isSTDIO: server.isSTDIO))
                    .codyGroupedRow()
                if server.isSTDIO {
                    detailRow(AppLocalized("Command"), server.command ?? "")
                        .codyGroupedRow()
                    if let args = MCPServerDetailRules.argsLine(server.args) {
                        detailRow(AppLocalized("Arguments"), args)
                            .codyGroupedRow()
                    }
                    LabeledContent(AppLocalized("Startup timeout (seconds)"),
                                   value: server.startupTimeoutSeconds.map(String.init) ?? AppLocalized("Default 60"))
                        .codyGroupedRow()
                } else {
                    let url = server.url ?? ""
                    // Long-press copies the URL, like a skill's source URL.
                    detailRow(AppLocalized("Server URL"), url, selectable: false)
                        .modifier(SkillSourceURLContextMenu(url: url.isEmpty ? nil : url,
                                                            title: AppLocalized("Copy URL")) {})
                        .codyGroupedRow()
                    if server.oauth != nil {
                        LabeledContent("OAuth") {
                            CodyStatusPill(
                                localized: authorized ? AppLocalized("Authorized") : AppLocalized("Not authorized"),
                                tone: authorized ? .success : .neutral,
                                dotColor: authorized ? CodyColors.connectionReady : nil
                            )
                        }
                        .codyGroupedRow()
                    }
                }
            }

            if let note = MCPServerDetailRules.trimmedNote(server.note) {
                Section {
                    Text(note).textSelection(.enabled)
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                        .codyGroupedRow()
                } header: {
                    Text(AppLocalized("Note"))
                        .settingsSectionHeading()
                }
            }

            if !headerNames.isEmpty {
                Section {
                    namesText(headerNames)
                        .codyGroupedRow()
                } header: {
                    Text(AppLocalized("Custom Headers"))
                        .settingsSectionHeading()
                } footer: {
                    if envNames.isEmpty { valuesHiddenNote.settingsSectionFooter() }
                }
            }
            if !envNames.isEmpty {
                Section {
                    namesText(envNames)
                        .codyGroupedRow()
                } header: {
                    Text(AppLocalized("Environment Variables"))
                        .settingsSectionHeading()
                } footer: {
                    valuesHiddenNote.settingsSectionFooter()
                }
            }
        }
        .codyGroupedListCanvas()
        .navigationTitle(server.id)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: server.id) {
            guard server.oauth != nil else { return }
            authorized = MCPOAuthController.isAuthorized(server: server.id)
        }
    }

    private var valuesHiddenNote: some View {
        Text(AppLocalized("Values are hidden because they can contain keys. View or edit them in Settings → MCP Integrations."))
    }

    private func namesText(_ names: [String]) -> some View {
        Text(names.joined(separator: "\n"))
            .font(CodyTypography.code)
            .foregroundStyle(CodyColors.textPrimary)
            .textSelection(.enabled)
    }

    /// Label above a full-width monospaced value. Not selectable when the row
    /// carries a long-press menu, which text selection would otherwise take.
    @ViewBuilder
    private func detailRow(_ label: String, _ value: String, selectable: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.xxs) {
            Text(label)
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
            if selectable {
                Text(value)
                    .font(CodyTypography.code)
                    .foregroundStyle(CodyColors.textPrimary)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(CodyTypography.code)
                    .foregroundStyle(CodyColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
