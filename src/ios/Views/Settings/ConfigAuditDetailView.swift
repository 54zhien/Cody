import SwiftUI

/// [T-config-readable] Logs → Config Changes → one record.
///
/// Shows what the change meant in words (the readable description stored with
/// the row when it was requested), then the raw setting path and full old /
/// new JSON. Rows written before readable descriptions existed have no
/// description; they say so and show the raw change only — names are NOT
/// re-derived from today's data, which could have changed since.
struct ConfigAuditDetailView: View {
    let entry: ConfigAuditEntry
    @State private var status: ConfigAuditStatus
    @State private var confirmRevert = false
    @State private var reverting = false
    @State private var resultTitle: String?
    @State private var resultBody = ""

    init(entry: ConfigAuditEntry) {
        self.entry = entry
        _status = State(initialValue: entry.status)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Status") { ConfigAuditStatusBadge(status: status) }
                    .settingsRowSurface()
                LabeledContent("Changed by") { Text(Self.actorLabel(entry.actor)) }
                    .settingsRowSurface()
                LabeledContent("Requested") {
                    Text(entry.at.formatted(date: .abbreviated, time: .standard))
                }
                    .settingsRowSurface()
                if let confirmed = entry.confirmedAt {
                    LabeledContent("Resolved") {
                        Text(confirmed.formatted(date: .abbreviated, time: .standard))
                    }
                        .settingsRowSurface()
                }
            }

            if let caption = entry.caption, !caption.isEmpty {
                Section {
                    Text(verbatim: caption)
                        .textSelection(.enabled)
                        .settingsRowSurface()
                } header: {
                    Text("Note from the assistant")
                        .settingsSectionHeading()
                }
            }

            Section {
                if let readable = entry.readable {
                    Text(verbatim: readable.displayText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .settingsRowSurface()
                } else {
                    Label("This record predates readable descriptions, so only the raw change is shown.",
                          systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .settingsRowSurface()
                }
            } header: {
                Text("What changed")
                    .settingsSectionHeading()
            }

            Section {
                rawBlock("Setting", entry.key)
                    .settingsRowSurface()
                rawBlock("Before", Self.prettyJSON(entry.oldValueJSON))
                    .settingsRowSurface()
                rawBlock("After", Self.prettyJSON(entry.newValueJSON))
                    .settingsRowSurface()
            } header: {
                Text("Raw change")
                    .settingsSectionHeading()
            }

            if status == .applied {
                Section {
                    Button(role: .destructive) {
                        confirmRevert = true
                    } label: {
                        SettingsIconLabel(title: Text("Revert This Change"), systemImage: "arrow.uturn.backward", tint: .red)
                    }
                    .disabled(reverting)
                        .settingsRowSurface()
                }
            } else if status == .reverted {
                Section {
                    Label("Reverted", systemImage: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(CodyCategoryTint.purple.color)
                        .settingsRowSurface()
                }
            }
        }
        .settingsGroupedCanvas()
        .listStyle(.insetGrouped)
        .navigationTitle("Change Details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Revert this change?", isPresented: $confirmRevert, titleVisibility: .visible) {
            Button("Revert", role: .destructive) { performRevert() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(verbatim: ConfigAuditRevert.dialogMessage(for: entry))
        }
        .alert(resultTitle ?? "", isPresented: Binding(
            get: { resultTitle != nil },
            set: { if !$0 { resultTitle = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(verbatim: resultBody)
        }
    }

    @ViewBuilder
    private func rawBlock(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func performRevert() {
        reverting = true
        Task {
            let outcome = await ConfigAuditRevert.perform(entry)
            reverting = false
            if outcome.ok {
                status = .reverted
                resultTitle = AppLocalized("Reverted")
                resultBody = AppLocalized("Setting restored.")
            } else {
                resultTitle = AppLocalized("Revert Failed")
                resultBody = outcome.reason
            }
        }
    }

    static func actorLabel(_ actor: ConfigAuditActor) -> String {
        switch actor {
        case .agent: return AppLocalized("Assistant")
        case .user: return AppLocalized("You")
        case .agentRevert: return AppLocalized("Assistant (revert)")
        case .userRevert: return AppLocalized("You (revert)")
        }
    }

    /// Audit JSON → readable raw text: pretty-printed objects / arrays, bare
    /// strings unquoted, "—" for an empty side (add / remove).
    static func prettyJSON(_ json: String) -> String {
        if json.isEmpty { return "—" }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return json
        }
        if let s = obj as? String { return s }
        guard obj is [Any] || obj is [String: Any],
              let out = try? JSONSerialization.data(withJSONObject: obj,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: out, encoding: .utf8) else {
            return json
        }
        return text
    }
}

/// Status capsule shared by the audit list and the detail page.
struct ConfigAuditStatusBadge: View {
    let status: ConfigAuditStatus

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch status {
        case .applied: return .green
        case .rejected: return .gray
        case .timeout: return .orange
        case .reverted: return .purple
        }
    }
}

/// User-initiated revert from Logs, shared by the list row and the detail page.
enum ConfigAuditRevert {
    /// The Logs sheet cannot stack ConfigConfirmSheet, so the local dialog is
    /// the confirmation and the bridge runs with `skipConfirmation: true`.
    static func perform(_ entry: ConfigAuditEntry) async -> (ok: Bool, reason: String) {
        let id = entry.id
        let (ok, reason) = await Task.detached { () -> (Bool, String?) in
            let result = ConfigOffloadBridge.auditRevert(
                id: id,
                actorRaw: "user-revert",
                sessionId: nil,
                skipConfirmation: true
            )
            return ((result["ok"] as? Bool) == true, result["reason"] as? String)
        }.value
        if ok { return (true, "") }
        return (false, reason ?? AppLocalized("Unknown error"))
    }

    /// Dialog text: what will be undone, in words when the row has them.
    @MainActor static func dialogMessage(for entry: ConfigAuditEntry) -> String {
        if let readable = entry.readable {
            return AppLocalized("This undoes:") + "\n" + readable.displayText
        }
        return "\(entry.key)\n\(ConfigAuditDetailView.prettyJSON(entry.newValueJSON)) → \(ConfigAuditDetailView.prettyJSON(entry.oldValueJSON))"
    }
}
