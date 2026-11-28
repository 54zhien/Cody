import SwiftUI

// [T-sub-agents-v1] Settings › Sub Agents — the switch and the definitions in
// one place. The type keeps its name (the navigation link that reaches it is
// wired by name in several places, and 8f09afa45 established that this rename
// wave only changes user-visible text, not identifiers).
//
// This page OWNS the `agent.tools.agents.enabled` switch. Settings › Tools no
// longer mentions agents at all — not even a read-only row — so there is
// exactly one place to look and no cross-reference to keep in sync.
struct HelperSettingsView: View {
    /// Legacy key of the switch this page used to own. No longer read by the
    /// tool gate; kept only so an old value never resurrects a toggle, and so
    /// `AgentToolSwitch.migrateLegacyIfNeeded()` can still consult it.
    static let legacyEnabledKey = "agent.helpers.enabled"

    @AppStorage(AgentToolSwitch.agents.key) private var agentsEnabled: Bool = AgentToolSwitch.agents.defaultValue
    @ObservedObject private var store = SubAgentStore.shared
    @State private var editorTarget: SubAgentEditorTarget?

    private var roster: [SubAgentDefinition] { store.subAgents }

    var body: some View {
        CodySettingsScrollPage {
            CodySettingsNovaSection(
                footer: "Delegate self-contained sub-tasks to a sub agent that works in its own hidden session and reports back. The same tool also lets the assistant check on or stop what it started. Several agents can run at once, so a large fan-out uses correspondingly more of your quota. On by default; when off, it is not offered to the model at all."
            ) {
                Toggle(isOn: $agentsEnabled) {
                    VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                        Text(AppLocalized("Sub Agents"))
                            .font(CodyTypography.bodyLarge)
                        Text(SubAgentDefinition.toolName)
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
                .tint(.green)
                .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
            }

            VStack(alignment: .leading, spacing: CodySpacing.sm) {
                rosterSection
                if !store.canAddSubAgent {
                    Text(String(format: AppLocalized("You can define up to %d sub agents."), SubAgentLimits.maxCount))
                        .settingsNovaFooter()
                }
            }
            .opacity(agentsEnabled ? 1 : 0.5)
        }
        .navigationTitle(AppLocalized("Sub Agents"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorTarget) { target in
            SubAgentEditorView(existing: target.definition)
        }
    }

    private var rosterSection: some View {
        CodySettingsNovaSection(
            "Sub Agents",
            footer: "The assistant picks a sub agent by its description, so write the description as “when to use this”. Order is the order it sees them in."
        ) {
            ForEach(roster) { definition in
                if definition.id != roster.first?.id {
                    CodySettingsNovaDivider(leadingInset: 18)
                }
                HStack(spacing: 0) {
                    Button {
                        editorTarget = SubAgentEditorTarget(definition: definition)
                    } label: {
                        row(definition)
                            .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
                    }
                    .buttonStyle(CodyPressableButtonStyle())

                    if !definition.isBuiltIn {
                        SettingsNovaRowMenu(title: "Actions for \(definition.displayName)") {
                            reorderActions(for: definition)
                            Button("Delete", role: .destructive) {
                                store.removeSubAgent(id: definition.id)
                            }
                        }
                        .padding(.trailing, CodySpacing.sm)
                    }
                }
            }
            if !roster.isEmpty { CodySettingsNovaDivider(leadingInset: 18) }
            CodySettingsNovaActionRow("Add Sub Agent", systemImage: nil) {
                editorTarget = SubAgentEditorTarget(definition: nil)
            }
            .disabled(!store.canAddSubAgent)
        }
    }

    @ViewBuilder
    private func reorderActions(for definition: SubAgentDefinition) -> some View {
        if let index = roster.firstIndex(where: { $0.id == definition.id }) {
            if index > roster.startIndex, !roster[index - 1].isBuiltIn {
                Button {
                    move(definition, by: -1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if index + 1 < roster.endIndex {
                Button {
                    move(definition, by: 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
    }

    private func row(_ def: SubAgentDefinition) -> some View {
        HStack(spacing: CodySpacing.smPlus) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(def.displayName)
                        .font(CodyTypography.titleMedium)
                    if def.isBuiltIn {
                        Text(AppLocalized("Built-in"))
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(CodyColors.interactiveSecondaryBg, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if !def.displayDescription.isEmpty {
                    Text(def.displayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(modelLabel(def))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: CodySpacing.sm)
            SettingsNovaDisclosure()
        }
    }

    private func modelLabel(_ def: SubAgentDefinition) -> String {
        if let gid = def.modelGroupId, let g = ProviderConfigStore.shared.group(for: gid) { return g.name }
        return AppLocalized("Auto")
    }

    private func move(_ definition: SubAgentDefinition, by offset: Int) {
        let definitions = roster
        guard let index = definitions.firstIndex(where: { $0.id == definition.id }) else { return }
        let target = index + offset
        guard definitions.indices.contains(target), !definitions[target].isBuiltIn else { return }
        var ids = definitions.map(\.id)
        ids.swapAt(index, target)
        store.reorderSubAgents(ids)
    }

}

/// What the editor sheet should open with. `.sheet(item:)` rather than a Bool
/// plus a payload, so presentation is driven by the value's identity.
struct SubAgentEditorTarget: Identifiable {
    let definition: SubAgentDefinition?
    var id: String { definition?.id ?? "new" }
}

/// Add / edit one sub agent. [T-sub-agents-v1]
struct SubAgentEditorView: View {
    let existing: SubAgentDefinition?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SubAgentStore.shared
    /// [T-subagent-own-store] The model-group picker reads provider
    /// configuration, which is a different store from the roster. Observed so
    /// the picker refreshes when groups change.
    @ObservedObject private var providerStore = ProviderConfigStore.shared

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var instructions = ""
    @State private var modelGroupId: String?
    @State private var thinkingOverride: ThinkingLevel?
    @State private var didSeed = false

    private var isBuiltIn: Bool { existing?.isBuiltIn ?? false }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameIsDuplicate: Bool {
        store.subAgentNameIsTaken(trimmedName, excluding: existing?.id)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
            && !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nameIsDuplicate
    }

    var body: some View {
        NavigationStack {
            CodySettingsScrollPage {
                // [T-sub-agents-v1] The built-in's name and description are
                // fixed. They are what the delegating model reads to decide
                // what to hand over, and it is the fallback every unnamed
                // delegation lands on — a user who rewrote them to something
                // vague would quietly degrade every delegation with no way to
                // get the original wording back. Model and Instructions stay
                // editable: those are genuinely the user's call.
                VStack(alignment: .leading, spacing: CodySpacing.sm) {
                    if isBuiltIn {
                        CodySettingsNovaSection("Name") {
                            Text(existing?.displayName ?? name)
                                .foregroundStyle(CodyColors.textSecondary)
                                .settingsNovaControlRow()
                        }
                    } else {
                        TextField(AppLocalized("Name"), text: $name)
                            .autocorrectionDisabled()
                            .settingsNovaField("Name")
                        counter(name.count, SubAgentLimits.nameMaxLength)
                    }

                    if nameIsDuplicate {
                        Text(AppLocalized("Another sub agent already uses this name."))
                            .foregroundStyle(CodyColors.statusErrorText)
                            .settingsNovaFooter()
                    }
                }

                if isBuiltIn {
                    CodySettingsNovaSection("Description", footer: "The built-in sub agent's name and description are fixed. You can still change its model and instructions.") {
                        Text(existing?.displayDescription ?? descriptionText)
                            .foregroundStyle(CodyColors.textSecondary)
                            .settingsNovaControlRow()
                    }
                } else {
                    VStack(alignment: .leading, spacing: CodySpacing.sm) {
                        TextField(AppLocalized("Description"), text: $descriptionText, axis: .vertical)
                            .lineLimit(2...4)
                            .settingsNovaField("Description")
                        counter(descriptionText.count, SubAgentLimits.descriptionMaxLength)
                        Text("Describe when this sub agent should be used. Keep it short — details go in Instructions.")
                            .settingsNovaFooter()
                    }
                }

                VStack(alignment: .leading, spacing: CodySpacing.sm) {
                    TextField(AppLocalized("Instructions"), text: $instructions, axis: .vertical)
                        .lineLimit(4...12)
                        .settingsNovaField("Instructions")
                    counter(instructions.count, SubAgentLimits.instructionsMaxLength)
                    Text(isBuiltIn ? "These instructions apply to every delegation that does not name a sub agent. Custom sub agents use their own." : "These instructions apply only to this sub agent.")
                        .settingsNovaFooter()
                }

                CodySettingsNovaSection("Model", footer: "Auto lets the assistant choose per task: the same model as the conversation, your Default group for hard reasoning, or your light group for simple well-defined work. Pick a specific Model Group instead to run this sub agent on it every time.") {
                    HStack {
                        Text(AppLocalized("Model"))
                            .foregroundStyle(CodyColors.textPrimary)
                        Spacer(minLength: CodySpacing.sm)
                        Picker(AppLocalized("Model"), selection: $modelGroupId) {
                            Text(AppLocalized("Auto")).tag(String?.none)
                            ForEach(providerStore.config.modelGroups) { group in
                                Text(group.name).tag(String?.some(group.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(CodyColors.textSecondary)
                    }
                    .settingsNovaControlRow()
                }

                // [T-subagent-thinking-override] Same shape as a Model Group's
                // own Session Defaults section: a toggle for "set one at all",
                // and an intensity picker once it is on.
                CodySettingsNovaSection("Reasoning", footer: thinkingOverride == nil ? "Off: runs use the reasoning level of the Model Group above, or of the conversation that delegated when the model is Auto." : "Every run of this sub agent uses this level, overriding the Model Group's own default. Models that cannot reason this hard are clamped to their own ceiling.") {
                    Toggle(isOn: Binding(
                        get: { thinkingOverride != nil },
                        set: { thinkingOverride = $0 ? (thinkingOverride ?? .medium) : nil }
                    )) {
                        Text(AppLocalized("Override Reasoning"))
                    }
                    .tint(.green)
                    .settingsNovaControlRow()

                    if thinkingOverride != nil {
                        CodySettingsNovaDivider(leadingInset: 18)
                        let levels = overrideThinkingLevels
                        Picker(AppLocalized("Intensity"), selection: Binding(
                            get: {
                                // Same snap-to-offered-tier rule the group
                                // picker uses: a segmented picker whose
                                // selection matches no tag renders with nothing
                                // highlighted.
                                let current = thinkingOverride ?? .medium
                                if levels.contains(current) { return current }
                                return levels.last(where: { $0 <= current })
                                    ?? levels.first
                                    ?? current
                            },
                            set: { thinkingOverride = $0 }
                        )) {
                            ForEach(levels, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                            .settingsNovaControlRow()
                    }
                }
                SettingsNovaEditorActions(isSaveDisabled: !isValid, save: save) {
                    dismiss()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? AppLocalized("New Sub Agent") : AppLocalized("Edit Sub Agent"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: seed)
        }
    }

    /// [T-subagent-thinking-override] Tiers the intensity picker offers.
    ///
    /// With a group pinned these are the group's own — derived the same way
    /// `ModelGroupDetailView` does, as the UNION of what its reasoning-capable
    /// members support, so the list matches what the user sees there. On Auto
    /// there is no group to ask (the model picks one per task), so every tier
    /// is offered; the request path clamps per model anyway
    /// (`min(level, model.catalogMaxThinkingLevel)`).
    private var overrideThinkingLevels: [ThinkingLevel] {
        let store = ProviderConfigStore.shared
        guard let gid = modelGroupId, let group = store.group(for: gid) else {
            return ThinkingLevel.allCases.filter { $0 != .off }
        }
        let entries = group.memberEntryIds.compactMap { store.entry(for: $0) }
            .filter { $0.effectiveMaxThinkingLevel != .off }
        let ceiling = entries.map(\.effectiveMaxThinkingLevel).max() ?? .xhigh
        let union = Set(entries.flatMap { $0.selectableThinkingLevels })
        guard !union.isEmpty else {
            return ThinkingLevel.allCases.filter { $0 != .off && $0 <= ceiling }
        }
        return union.filter { $0 <= ceiling }.sorted()
    }

    private func counter(_ count: Int, _ limit: Int) -> some View {
        HStack {
            Spacer()
            Text("\(count)/\(limit)")
                .font(.caption2)
                .foregroundStyle(count > limit ? CodyColors.statusErrorText : CodyColors.textSecondary)
        }
        .padding(.horizontal, CodyMetrics.Settings.rowPaddingH)
        .padding(.bottom, CodySpacing.sm)
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        guard let existing else { return }
        name = existing.name
        descriptionText = existing.description
        instructions = existing.instructions
        modelGroupId = existing.modelGroupId
        thinkingOverride = existing.thinkingLevelOverride
    }

    private func save() {
        // Clamp here as well as in the store: a paste can exceed the limit even
        // though the counter turns red.
        let def = SubAgentDefinition(
            id: existing?.id ?? UUID().uuidString,
            name: String(trimmedName.prefix(SubAgentLimits.nameMaxLength)),
            description: String(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(SubAgentLimits.descriptionMaxLength)),
            instructions: String(instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(SubAgentLimits.instructionsMaxLength)),
            modelGroupId: modelGroupId,
            thinkingLevelOverride: thinkingOverride,
            isBuiltIn: isBuiltIn,
            sortOrder: existing?.sortOrder ?? 0
        )
        store.upsertSubAgent(def)
        dismiss()
    }
}
