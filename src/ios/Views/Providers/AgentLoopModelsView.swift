import SwiftUI

/// Inline section for ModelGroupsView — manages models available via cody-model-use.
/// Supports both individual model entries and entire model groups.
/// Sheet bindings are passed in from the parent to avoid hanging .sheet on a Section inside a List.
struct AgentLoopModelsSection: View {
    @ObservedObject private var store = ProviderConfigStore.shared
    @Binding var showAddModels: Bool
    @Binding var showAddGroups: Bool

    private var currentEntries: [ModelEntry] {
        store.agentLoopModelEntryIds.compactMap { store.entry(for: $0) }
    }

    private var currentGroups: [ModelGroup] {
        store.agentLoopGroupIds.compactMap { store.group(for: $0) }
    }

    var body: some View {
        Section {
            if currentGroups.isEmpty && currentEntries.isEmpty {
                Text("No models or groups added")
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .codyGroupedRow()
            }

            if !currentGroups.isEmpty {
                ForEach(currentGroups) { group in
                    groupRow(group)
                        .codyGroupedRow()
                }
                .onMove(perform: moveGroups)
                .onDelete(perform: deleteGroups)
            }

            if !currentEntries.isEmpty {
                ForEach(currentEntries) { entry in
                    entryRow(entry)
                        .codyGroupedRow()
                }
                .onMove(perform: moveEntries)
                .onDelete(perform: deleteEntries)
            }

            Menu {
                Button {
                    showAddModels = true
                } label: {
                    Label("Add Models", systemImage: "cpu")
                }
                if !availableGroups.isEmpty {
                    Button {
                        showAddGroups = true
                    } label: {
                        Label("Add Group", systemImage: "square.stack.3d.up")
                    }
                }
            } label: {
                Label("Add Models or Groups", systemImage: "plus.circle")
                    .font(CodyTypography.bodyMedium.weight(.medium))
                    .foregroundStyle(CodyColors.textAccent)
            }
            .codyGroupedRow()
        } header: {
            HStack {
                Text("Models Cody Can Call at Runtime")
                    .codySectionHeaderText()
                Spacer()
                if !currentEntries.isEmpty || !currentGroups.isEmpty {
                    EditButton()
                        .font(CodyTypography.bodySmall)
                }
            }
        } footer: {
            Text("During a Cody task, the agent calls these models for sub-tasks such as generating an image or summarizing text — work its own model can't do. Also callable from the terminal via cody-model-use. Only these are visible to the agent.")
        }
    }

    // MARK: - Rows

    private func groupRow(_ group: ModelGroup) -> some View {
        HStack(spacing: CodySpacing.md) {
            CodySettingsIconBadge(systemImage: "square.stack.3d.up.fill", tint: .blue)

            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(group.name)
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.textPrimary)
                let count = group.memberEntryIds.count
                Text(AppLocalized("\(count) models") + " · \(group.strategy == .fallback ? AppLocalized("Fallback") : AppLocalized("Load Balance"))")
                    .font(CodyTypography.labelSmall.monospacedDigit())
                    .foregroundStyle(CodyColors.textTertiary)
            }

            Spacer()

            CodyStatusPill("Group", tone: .neutral)
        }
    }

    private func entryRow(_ entry: ModelEntry) -> some View {
        HStack(spacing: CodySpacing.smPlus) {
            Circle()
                .fill(CodyProviderVisuals.tint(forProviderName: entry.model.provider).color)
                .frame(width: 6, height: 6)
                .frame(width: CodySpacing.lg)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(entry.model.displayName)
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textPrimary)
                HStack(spacing: CodySpacing.xs) {
                    if let instance = store.instance(for: entry.providerInstanceId) {
                        Text(instance.label)
                            .font(CodyTypography.labelSmall)
                            .foregroundStyle(CodyColors.textTertiary)
                    }
                    let badges = CodyProviderVisuals.modalityBadges(for: entry.model)
                    if !badges.isEmpty {
                        Text("·")
                            .font(CodyTypography.labelSmall)
                            .foregroundStyle(CodyColors.textTertiary)
                        ForEach(badges, id: \.self) { badge in
                            CodyModalityCapsule(text: badge)
                        }
                    }
                }
            }

            Spacer()

            Text(entry.model.provider)
                .font(CodyTypography.labelSmall)
                .foregroundStyle(CodyColors.textSecondary)
        }
    }

    // MARK: - Available groups (not yet added)

    private var availableGroups: [ModelGroup] {
        let existing = Set(store.agentLoopGroupIds)
        return store.modelGroups.filter { !existing.contains($0.id) }
    }

    // MARK: - Actions

    // The IndexSet SwiftUI hands us is based on `currentEntries`, which is the raw
    // id array filtered through `compactMap { store.entry(for: $0) }`. If the raw
    // `agentLoopModelEntryIds` contains any orphan ids (entries that no longer
    // resolve — e.g. from deleted providers or iCloud-synced ids with no local
    // counterpart), the two arrays have different lengths and indexing into the
    // raw array with visible indices corrupts the result — reorders snap back,
    // deletes remove the wrong row. Work on visible ids and drop orphans in the
    // same pass so the store stays clean.
    private func moveEntries(from source: IndexSet, to destination: Int) {
        var visibleIds = currentEntries.map { $0.id }
        visibleIds.move(fromOffsets: source, toOffset: destination)
        store.agentLoopModelEntryIds = visibleIds
    }

    private func deleteEntries(at offsets: IndexSet) {
        var visibleIds = currentEntries.map { $0.id }
        visibleIds.remove(atOffsets: offsets)
        store.agentLoopModelEntryIds = visibleIds
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        var visibleIds = currentGroups.map { $0.id }
        visibleIds.move(fromOffsets: source, toOffset: destination)
        store.agentLoopGroupIds = visibleIds
    }

    private func deleteGroups(at offsets: IndexSet) {
        var visibleIds = currentGroups.map { $0.id }
        visibleIds.remove(atOffsets: offsets)
        store.agentLoopGroupIds = visibleIds
    }
}

// MARK: - Add Groups Sheet

struct AddAgentLoopGroupsSheet: View {
    @ObservedObject private var store = ProviderConfigStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroupIds: Set<String> = []

    private var availableGroups: [ModelGroup] {
        let existing = Set(store.agentLoopGroupIds)
        return store.modelGroups.filter { !existing.contains($0.id) }
    }

    var body: some View {
        List {
            if availableGroups.isEmpty {
                Section {
                    Text("All groups are already added.")
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CodySpacing.lg)
                        .codyGroupedRow()
                }
            }

            ForEach(availableGroups) { group in
                Button {
                    toggleSelection(group.id)
                } label: {
                    HStack(spacing: CodySpacing.smPlus) {
                        Image(systemName: selectedGroupIds.contains(group.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selectedGroupIds.contains(group.id) ? CodyColors.interactivePrimaryBg : CodyColors.iconTertiary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                            Text(group.name)
                                .font(CodyTypography.titleSmall)
                                .foregroundStyle(CodyColors.textPrimary)
                            let entries = group.memberEntryIds.compactMap { store.entry(for: $0) }
                            let names = entries.prefix(3).map(\.model.displayName)
                            let suffix = entries.count > 3 ? " +\(entries.count - 3)" : ""
                            Text(names.joined(separator: ", ") + suffix)
                                .font(CodyTypography.labelSmall)
                                .foregroundStyle(CodyColors.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("\(group.memberEntryIds.count) models")
                            .font(CodyTypography.labelSmall.monospacedDigit())
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
                .codyGroupedRow()
            }
        }
        .codyGroupedListCanvas()
        .navigationTitle("Add Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add (\(selectedGroupIds.count))") {
                    addSelected()
                }
                .font(.body.weight(.semibold))
                .disabled(selectedGroupIds.isEmpty)
            }
        }
    }

    private func toggleSelection(_ groupId: String) {
        if selectedGroupIds.contains(groupId) {
            selectedGroupIds.remove(groupId)
        } else {
            selectedGroupIds.insert(groupId)
        }
    }

    private func addSelected() {
        for id in selectedGroupIds.sorted() {
            store.addAgentLoopGroup(id)
        }
        dismiss()
    }
}
