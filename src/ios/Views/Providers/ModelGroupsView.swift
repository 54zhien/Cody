import SwiftUI

/// Lists all model groups with default badges, and allows creating new groups.
struct ModelGroupsView: View {
    @ObservedObject private var store = ProviderConfigStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCreateGroup = false
    @State private var newGroupName = ""
    @State private var showAddAgentModels = false
    @State private var showAddAgentGroups = false
    @State private var forceSyncToast: String?
    /// [T-provider-group-swipe-actions] Swipe-to-edit / swipe-to-delete targets.
    /// Edit pushes the same detail screen the row taps into; delete is held here
    /// until the confirmation alert is answered.
    @State private var editingGroupId: String?
    @State private var pendingDeleteGroup: ModelGroup?
    @AppStorage("cloudSync.v2.enabled") private var iCloudSyncEnabled: Bool = false

    var body: some View {
        List {
            if store.modelGroups.isEmpty {
                Section {
                    CodyEmptyStateCard(
                        systemImage: "square.stack.3d.up",
                        title: "No model groups",
                        subtitle: "Groups let you combine models for fallback or load balancing."
                    ) {
                        Button {
                            showCreateGroup = true
                            newGroupName = ""
                        } label: {
                            Label(AppLocalized("New Group"), systemImage: "plus")
                                .font(CodyTypography.labelLarge)
                        }
                        .buttonStyle(CodyPrimaryCapsuleButtonStyle())
                    }
                    .codyGroupedRow()
                }
            }

            if !store.modelGroups.isEmpty {
                Section {
                    ForEach(store.modelGroups) { group in
                        NavigationLink {
                            ModelGroupDetailView(groupId: group.id)
                        } label: {
                            GroupRow(group: group)
                        }
                        .codyGroupedRow()
                        // [T-provider-group-swipe-actions] Explicit swipe
                        // actions REPLACE the previous `.onDelete`, which gave
                        // a swipe-to-delete with NO confirmation: a group can
                        // be a default/voice/vision target and removing it
                        // silently clears those pointers (see
                        // ProviderConfigStore.removeGroup), so one careless
                        // swipe could reconfigure routing with no undo.
                        // Reordering is unaffected — `.onMove` stays, and UIKit
                        // arbitrates horizontal vs vertical drags itself.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteGroup = group
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingGroupId = group.id
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(CodyColors.textAccent)
                        }
                    }
                    .onMove(perform: moveGroups)
                    // Retained so the EditButton's red-minus delete still
                    // exists; it now routes through `pendingDeleteGroup` and
                    // therefore asks for confirmation like the swipe does.
                    .onDelete(perform: deleteGroups)
                } header: {
                    HStack {
                        Text("Groups")
                            .codySectionHeaderText()
                        Spacer()
                        EditButton()
                            .font(CodyTypography.bodySmall)
                            .textCase(nil)
                    }
                }
            }

            // Default assignments
            if !store.modelGroups.isEmpty {
                Section {
                    GroupSlotPicker(
                        label: "Default Primary",
                        selection: Binding(
                            get: { store.defaultPrimaryGroupId },
                            set: { store.defaultPrimaryGroupId = $0 }
                        )
                    )
                    .codyGroupedRow()
                    GroupSlotPicker(
                        label: "Default Sub",
                        selection: Binding(
                            get: { store.defaultSubGroupId },
                            set: { store.defaultSubGroupId = $0 }
                        )
                    )
                    .codyGroupedRow()
                    GroupSlotPicker(
                        label: "Voice Input",
                        selection: Binding(
                            get: { store.voiceInputGroupId },
                            set: { store.voiceInputGroupId = $0 }
                        ),
                        voiceDirection: .input
                    )
                    .codyGroupedRow()
                    GroupSlotPicker(
                        label: "Voice Output",
                        selection: Binding(
                            get: { store.voiceOutputGroupId },
                            set: { store.voiceOutputGroupId = $0 }
                        ),
                        voiceDirection: .output
                    )
                    .codyGroupedRow()
                    GroupSlotPicker(
                        label: "Vision Input",
                        selection: Binding(
                            get: { store.visionGroupId },
                            set: { store.visionGroupId = $0 }
                        ),
                        isVision: true
                    )
                    .codyGroupedRow()
                } header: {
                    Text("Defaults")
                        .codySectionHeaderText()
                } footer: {
                    Text("Primary is used for main agent tasks. Sub is used for lightweight tasks like title generation. Voice Input/Output pick a group whose audio-capable models drive speech-to-text and text-to-speech; if none is set, the offline System voice is used. Vision Input picks a group whose image-capable models describe images when the chat model cannot see them itself; if none is set, models without vision cannot read images at all.")
                }
            }

            // Agent Loop Models
            AgentLoopModelsSection(showAddModels: $showAddAgentModels,
                                   showAddGroups: $showAddAgentGroups)
        }
        .codyGroupedListCanvas()
        .navigationTitle("Model Groups")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAgentModels) {
            NavigationStack {
                UnifiedModelPicker(config: .agentLoopAddModels())
            }
        }
        .sheet(isPresented: $showAddAgentGroups) {
            NavigationStack {
                AddAgentLoopGroupsSheet()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showCreateGroup = true
                        newGroupName = ""
                    } label: {
                        Label(AppLocalized("New Group"), systemImage: "plus")
                    }
                    if #available(iOS 17.0, *), iCloudSyncEnabled {
                        Divider()
                        Button {
                            Task { await forceSyncGroups() }
                        } label: {
                            Label(AppLocalized("Force iCloud Sync"),
                                  systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppLocalized("New Group"))
            }
        }
        .overlay(alignment: .top) {
            if let msg = forceSyncToast {
                Text(msg)
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.vertical, CodySpacing.smPlus)
                    .background(CodyColors.interactivePrimaryBg, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .padding(.top, CodySpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: forceSyncToast)
        // [T-provider-group-swipe-actions] Swipe-Edit reuses the row's own
        // destination.
        //
        // [T-swipe-edit-white-screen] Value-driven: the destination is built
        // from the id captured at push time rather than re-read from
        // `editingGroupId`, which could read back empty mid-swipe-retraction
        // and push a blank, inescapable screen. See SwipeEditDestination.swift.
        .swipeEditDestination(item: $editingGroupId) { id in
            ModelGroupDetailView(groupId: id)
        }
        // Names the group and spells out the consequence the store actually
        // has: removeGroup clears any default / voice / vision pointer aimed
        // at it, which is not obvious from "delete a group".
        .alert(
            AppLocalized("Delete Group"),
            isPresented: Binding(
                get: { pendingDeleteGroup != nil },
                set: { if !$0 { pendingDeleteGroup = nil } }
            ),
            presenting: pendingDeleteGroup
        ) { group in
            Button("Delete", role: .destructive) {
                store.removeGroup(group.id)
                pendingDeleteGroup = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteGroup = nil }
        } message: { group in
            Text("Delete \"\(group.name)\"? Any default, voice, or vision selection pointing at this group will be cleared. The models themselves are not deleted.")
        }
        .alert("New Group", isPresented: $showCreateGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Create") { createGroup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new model group.")
        }
    }

    // MARK: - Actions

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let group = ModelGroup(name: trimmed, memberEntryIds: [])
        store.addGroup(group)
        // Auto-set as primary default if it's the first group
        if store.modelGroups.count == 1 {
            store.defaultPrimaryGroupId = group.id
        }
    }

    /// [T-provider-group-swipe-actions] Edit-mode (red minus) deletion.
    ///
    /// Kept wired to `.onDelete` so the EditButton path kicks off the SAME
    /// confirmation the swipe does, instead of deleting outright as it used to.
    /// Only the first offset is honoured because the alert names one group;
    /// the list has no multi-select delete, so an IndexSet here is always a
    /// single row in practice.
    private func deleteGroups(at offsets: IndexSet) {
        let groups = store.modelGroups
        guard let index = offsets.first, groups.indices.contains(index) else { return }
        pendingDeleteGroup = groups[index]
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        var ids = store.modelGroups.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        store.reorderGroups(ids)
    }

    @available(iOS 17.0, *)
    private func forceSyncGroups() async {
        _ = await ForceSyncHelper.markProvidersDirty()
        await ForceSyncHelper.bidirectionalSync(recordTypes: ["ProviderConfig", "ProviderConfigV2"])
        forceSyncToast = AppLocalized("Syncing model groups via iCloud")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            forceSyncToast = nil
        }
    }
}

// MARK: - Group Row

private struct GroupRow: View {
    let group: ModelGroup
    @ObservedObject private var store = ProviderConfigStore.shared

    private var isPrimaryDefault: Bool {
        store.defaultPrimaryGroupId == group.id
    }

    private var isSubDefault: Bool {
        store.defaultSubGroupId == group.id
    }

    private var memberSummary: String {
        let entries = group.memberEntryIds.compactMap { store.entry(for: $0) }
        if entries.isEmpty { return AppLocalized("No models") }
        let names = entries.prefix(3).map(\.model.displayName)
        let suffix = entries.count > 3 ? " +\(entries.count - 3)" : ""
        return names.joined(separator: ", ") + suffix
    }

    /// [T-ios-modelgroup-modality-icons] The group's TOP-2 most distinctive
    /// modalities (across both inputs AND outputs), shown as icons after the
    /// title so the user can tell at a glance what the group is for (and which to
    /// avoid in a model picker). We aggregate every member model's effective
    /// modality (override else inferred) into one set, then pick the two
    /// highest-priority flags present — generation outputs and special audio/
    /// vision modalities rank above plain text, which is implied for every model.
    ///
    /// Priority (most distinctive first): video-out > image-out > audio-out(TTS)
    /// > audio-in(transcription) > video-in > image-in > pdf-in > text-out.
    /// `textInput` is never shown (universal, pure noise).
    private static let modalityPriority: [ModelModality] = [
        .videoOutput, .imageOutput, .audioOutput,
        .audioInput, .videoInput, .imageInput, .pdfInput,
        .textOutput,
    ]

    private var topModalities: [ModelModality] {
        var combined: ModelModality = []
        for entry in group.memberEntryIds.compactMap({ store.entry(for: $0) }) {
            let model = entry.model
            // Same effective-modality resolution as ProviderInstanceDetailView.
            combined.formUnion(model.modalityOverride ?? model.capabilities.supportedModalities)
        }
        return Self.modalityPriority.filter { combined.contains($0) }.prefix(2).map { $0 }
    }

    /// Icon + accessibility label + color for a single modality flag. Output
    /// (generation) modalities use the "generate"-style glyph + tint; input
    /// modalities use a muted secondary glyph — matching
    /// ProviderInstanceDetailView.modalityIcons.
    @ViewBuilder
    private func modalityIcon(_ modality: ModelModality) -> some View {
        switch modality {
        case .videoOutput:
            Image(systemName: "video.badge.plus")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyCategoryTint.blue.color)
                .accessibilityLabel(AppLocalized("Video generation"))
        case .imageOutput:
            Image(systemName: "photo.badge.plus")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyCategoryTint.blue.color)
                .accessibilityLabel(AppLocalized("Image generation"))
        case .audioOutput:
            Image(systemName: "speaker.wave.2")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyCategoryTint.blue.color)
                .accessibilityLabel(AppLocalized("Speech output"))
        case .audioInput:
            Image(systemName: "waveform.badge.mic")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyColors.iconSecondary)
                .accessibilityLabel(AppLocalized("Speech transcription"))
        case .videoInput:
            Image(systemName: "video")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyColors.iconSecondary)
                .accessibilityLabel(AppLocalized("Video input"))
        case .imageInput:
            Image(systemName: "photo")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyColors.iconSecondary)
                .accessibilityLabel(AppLocalized("Image input"))
        case .pdfInput:
            Image(systemName: "doc")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyColors.iconSecondary)
                .accessibilityLabel(AppLocalized("PDF input"))
        case .textOutput:
            Image(systemName: "text.alignleft")
                .font(CodyTypography.bodySmall).foregroundStyle(CodyColors.iconSecondary)
                .accessibilityLabel(AppLocalized("Text generation"))
        default:
            EmptyView()
        }
    }

    var body: some View {
        HStack(spacing: CodySpacing.md) {
            CodySettingsIconBadge(
                systemImage: group.strategy == .fallback ? "arrow.down.circle" : "arrow.triangle.branch",
                tint: group.strategy == .fallback ? .blue : .orange
            )

            VStack(alignment: .leading, spacing: CodySpacing.xs) {
                HStack(spacing: CodySpacing.xsPlus) {
                    Text(group.name)
                        .font(CodyTypography.titleMedium)
                        .foregroundStyle(CodyColors.textPrimary)
                    // [T-ios-modelgroup-modality-icons] Mark the group's top-2 most
                    // distinctive modalities (inputs + outputs) right after the title,
                    // in priority order, for at-a-glance "what is this group for".
                    ForEach(topModalities, id: \.rawValue) { modality in
                        modalityIcon(modality)
                    }
                    Spacer()
                    // AppLocalized, not a bare literal: `CodyStatusPill` takes a
                    // `String` when using `localized:`.
                    if isPrimaryDefault {
                        CodyStatusPill(localized: AppLocalized("Primary"), tone: .accent)
                    }
                    if isSubDefault {
                        CodyStatusPill(localized: AppLocalized("Sub"), tone: .warning)
                    }
                }

                HStack(spacing: CodySpacing.xsPlus) {
                    Text(group.strategy == .fallback ? "Fallback" : "Load Balance")
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                    if group.strategy == .fallback {
                        Text("·")
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(CodyColors.textTertiary)
                        Text(group.fallbackStrategy == .always ? AppLocalized("Always") : AppLocalized("Default"))
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(group.fallbackStrategy == .always ? CodyColors.statusWarningText : CodyColors.textSecondary)
                    }
                    Text("·")
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textTertiary)
                    Text(AppLocalized("\(group.memberEntryIds.count) models"))
                        .font(CodyTypography.bodySmall.monospacedDigit())
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Text(memberSummary)
                    .font(CodyTypography.labelSmall)
                    .foregroundStyle(CodyColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, CodySpacing.xxs)
    }
}
