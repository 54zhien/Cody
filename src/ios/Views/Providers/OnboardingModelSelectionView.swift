import SwiftUI

/// Onboarding step 2: pick one or more models from all configured providers and create a "Default Models" group.
struct OnboardingModelSelectionView: View {
    @ObservedObject private var store = ProviderConfigStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var selectedModelEntryIds: [String] = []
    @State private var searchText: String = ""

    // [T-onboarding-model-fetch-fallback] Page-owned fetch state. The store's
    // own fetch (addInstance → refreshModels) is fire-and-forget and swallows
    // errors, so this page could not tell "still loading" from "failed" and
    // showed the same spinner for both, with Next disabled, indefinitely. The
    // page now runs its own bounded fetch for any enabled instance that has no
    // visible models yet; the spinner is only shown while THAT is in flight.
    @State private var isFetching = false
    @State private var fetchError: String?
    /// Which instance the manual-add sheet targets. Presented with
    /// `.sheet(item:)` so the choice and the presentation are one value.
    @State private var manualAddTarget: ManualAddTarget?

    private struct ManualAddTarget: Identifiable {
        let instanceId: String
        var id: String { instanceId }
    }

    /// All visible model entries across all enabled instances.
    private var allEntries: [ModelEntry] {
        store.instances
            .filter(\.isEnabled)
            .flatMap { store.visibleEntries(for: $0.id) }
    }

    var body: some View {
        List {
            if allEntries.isEmpty {
                if let fetchError, !isFetching {
                    // Failed / timed out with nothing to show: say so, and give
                    // the two ways forward. Manual add reuses the same sheet the
                    // provider detail page uses, so a model added here lands in
                    // the store exactly as one added later would.
                    Section {
                        VStack(alignment: .leading, spacing: CodySpacing.md) {
                            HStack(alignment: .top, spacing: CodySpacing.sm) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(CodyTypography.titleSmall)
                                    .foregroundStyle(CodyColors.statusWarningText)
                                    .accessibilityHidden(true)
                                Text("Could not fetch the model list automatically.")
                                    .font(CodyTypography.bodyMedium)
                                    .foregroundStyle(CodyColors.textPrimary)
                            }
                            // The detail line is the provider's own error; skip it
                            // when all we have is the generic headline again.
                            if fetchError != AppLocalized("Could not fetch the model list automatically.") {
                                Text(fetchError)
                                    .font(CodyTypography.bodySmall)
                                    .foregroundStyle(CodyColors.textSecondary)
                            }
                            HStack(spacing: CodySpacing.md) {
                                Button {
                                    fetchMissingModels()
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                        .font(CodyTypography.labelLarge)
                                        .foregroundStyle(CodyColors.textPrimary)
                                        .padding(.horizontal, CodySpacing.md)
                                        .frame(minHeight: CodyControlHeight.compact)
                                        .background(CodyColors.interactiveSecondaryBg, in: Capsule())
                                        .overlay {
                                            Capsule()
                                                .strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                                                .allowsHitTesting(false)
                                        }
                                }
                                .buttonStyle(.borderless)
                                manualAddButton
                            }
                        }
                        .padding(.vertical, CodySpacing.xs)
                        .codyGroupedRow()
                    } header: {
                        Text("Models")
                            .codySectionHeaderText()
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: CodySpacing.md) {
                            CodyShimmeringText("Loading models...")
                                .font(CodyTypography.bodyMedium)
                            VStack(alignment: .leading, spacing: CodySpacing.sm) {
                                CodySkeletonView(height: CodySpacing.lg, cornerRadius: CodyRadius.sm)
                                CodySkeletonView(width: 210, height: CodySpacing.lg, cornerRadius: CodyRadius.sm)
                                CodySkeletonView(width: 160, height: CodySpacing.lg, cornerRadius: CodyRadius.sm)
                            }
                        }
                        .padding(.vertical, CodySpacing.xs)
                        .codyGroupedRow()
                    } header: {
                        Text("Models")
                            .codySectionHeaderText()
                    } footer: {
                        Text("Fetching model list from your provider…")
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(CodyColors.textTertiary)
                    }
                }
            } else {
                // Group entries by provider instance
                let instanceIds = store.instances.filter(\.isEnabled).map(\.id)
                ForEach(instanceIds, id: \.self) { instanceId in
                    let entries = store.visibleEntries(for: instanceId).filter { entry in
                        searchText.isEmpty || entry.model.displayName.localizedCaseInsensitiveContains(searchText)
                    }
                    if !entries.isEmpty, let instance = store.instance(for: instanceId) {
                        Section {
                            ForEach(entries) { entry in
                                modelRow(entry: entry)
                                    .codyGroupedRow()
                            }
                        } header: {
                            Text(instance.label)
                                .codySectionHeaderText()
                        }
                    }
                }
            }
        }
        .codyGroupedListCanvas()
        .searchable(text: $searchText, prompt: "Filter models")
        .navigationTitle("Select Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Skip") { dismiss() }
                    .foregroundStyle(CodyColors.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Button {
                    createGroupAndDismiss()
                } label: {
                    Text("Next")
                        .font(CodyTypography.titleMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CodyPrimaryCapsuleButtonStyle())
                .disabled(selectedModelEntryIds.isEmpty)
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
        .sheet(item: $manualAddTarget) { target in
            AddCustomModelSheet(instanceId: target.instanceId)
        }
        .onAppear { fetchMissingModels() }
    }

    /// One button when a single provider is enabled; a menu of providers when
    /// several are, since a custom model must belong to exactly one instance.
    @ViewBuilder
    private var manualAddButton: some View {
        let targets = store.instances.filter(\.isEnabled)
        if targets.count == 1, let only = targets.first {
            Button {
                manualAddTarget = ManualAddTarget(instanceId: only.id)
            } label: {
                manualAddLabel
            }
            .buttonStyle(.borderless)
        } else if !targets.isEmpty {
            Menu {
                ForEach(targets) { inst in
                    Button(inst.label) { manualAddTarget = ManualAddTarget(instanceId: inst.id) }
                }
            } label: {
                manualAddLabel
            }
        }
    }

    private var manualAddLabel: some View {
        Label("Add Model Manually", systemImage: "plus")
            .font(CodyTypography.labelLarge)
            .foregroundStyle(CodyColors.textPrimary)
            .padding(.horizontal, CodySpacing.md)
            .frame(minHeight: CodyControlHeight.compact)
            .background(CodyColors.interactiveSecondaryBg, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
    }

    // MARK: - Fetch

    /// Fetch models for every enabled instance that has none yet, bounded by a
    /// page-level timeout so an upstream that never answers cannot pin the
    /// spinner. No-op while a fetch is already running or once anything is
    /// listed — the normal path (store fetch succeeded before this page
    /// appeared) is untouched.
    private func fetchMissingModels() {
        guard allEntries.isEmpty, !isFetching else { return }
        let targets = store.instances.filter { $0.isEnabled && store.visibleEntries(for: $0.id).isEmpty }
        guard !targets.isEmpty else {
            // Nothing to fetch and nothing listed (every provider disabled):
            // a spinner would never end, so show the failure state straight
            // away. The manual-add button hides itself when no instance is
            // enabled, leaving Skip as the way out.
            fetchError = AppLocalized("Could not fetch the model list automatically.")
            return
        }
        isFetching = true
        fetchError = nil
        Task { @MainActor in
            defer { isFetching = false }
            var errors: [String] = []
            do {
                errors = try await OnboardingModelFetch.withTimeout(seconds: OnboardingModelFetch.timeoutSeconds) {
                    await withTaskGroup(of: String?.self, returning: [String].self) { group in
                        for inst in targets {
                            group.addTask {
                                do {
                                    let result = try await ProviderConfigStore.fetchModelsWithFallback(inst, forceRefresh: true)
                                    await ProviderConfigStore.shared.replaceEntries(for: inst.id, models: result.models)
                                    return nil
                                } catch {
                                    return error.localizedDescription
                                }
                            }
                        }
                        var collected: [String] = []
                        for await e in group { if let e { collected.append(e) } }
                        return collected
                    }
                }
            } catch {
                errors = [error.localizedDescription]
            }
            // Only an EMPTY page is a failure the user has to act on; a partial
            // result (one of two providers answered) simply shows what arrived.
            if allEntries.isEmpty {
                fetchError = errors.first ?? AppLocalized("Could not fetch the model list automatically.")
            }
        }
    }

    @ViewBuilder
    private func modelRow(entry: ModelEntry) -> some View {
        let selectionIndex = selectedModelEntryIds.firstIndex(of: entry.id)
        let isSelected = selectionIndex != nil

        Button {
            if let idx = selectionIndex {
                selectedModelEntryIds.remove(at: idx)
            } else {
                selectedModelEntryIds.append(entry.id)
            }
        } label: {
            HStack(spacing: CodySpacing.md) {
                Text(entry.model.displayName)
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                Spacer(minLength: CodySpacing.sm)
                ZStack {
                    Circle()
                        .fill(isSelected ? CodyColors.interactivePrimaryBg : Color.clear)
                        .frame(width: CodySpacing.xxl, height: CodySpacing.xxl)
                    Circle()
                        .strokeBorder(
                            isSelected ? CodyColors.interactivePrimaryBg : CodyColors.borderHeavy,
                            lineWidth: 1.5
                        )
                        .frame(width: CodySpacing.xxl, height: CodySpacing.xxl)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(minHeight: CodyControlHeight.standard)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func createGroupAndDismiss() {
        let group = ModelGroup(
            name: "Default Models",
            memberEntryIds: selectedModelEntryIds,
            strategy: .fallback
        )
        store.addGroup(group)
        if store.defaultPrimaryGroupId == nil {
            store.defaultPrimaryGroupId = group.id
        }
        dismiss()
    }
}

// MARK: - Bounded fetch  [T-onboarding-model-fetch-fallback]

/// The timeout race behind the onboarding fetch, kept as a free-standing pure
/// helper so it is testable without the view or the store.
enum OnboardingModelFetch {
    /// Long enough for a slow /v1/models plus the models.dev fallback, short
    /// enough that a hung upstream stops looking like a frozen screen.
    static let timeoutSeconds: TimeInterval = 20

    struct TimeoutError: LocalizedError, Equatable {
        let seconds: TimeInterval
        var errorDescription: String? {
            AppLocalized("Timed out after \(Int(seconds)) seconds.")
        }
    }

    /// Runs `operation`, throwing `TimeoutError` if it has not finished within
    /// `seconds`. The loser is cancelled, cooperatively: a fetch that does not
    /// check for cancellation may still complete later, in which case its
    /// models simply appear and the error state clears itself (the failed
    /// section is only rendered while `allEntries` is empty).
    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(seconds: seconds)
            }
            // First to finish decides; the other is cancelled on scope exit.
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}
