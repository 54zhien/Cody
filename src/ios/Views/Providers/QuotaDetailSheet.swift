//
//  QuotaDetailSheet.swift
//  CodyApp
//
//  [T-quota-badge-ui] The full quota picture of one provider account, opened
//  from the gray pill on the model picker's provider header. Separate from
//  the provider's own detail page: this is read-only quota, nothing else.
//
//  - One card per canonical pool (QuotaPoolRow, detailed):
//    - amounts in their own unit, with the granted / topped-up breakdown;
//    - a progress bar only with a reliable percent (QuotaBarRules);
//    - a coloured status (QuotaToneRules): grey for unknown / expired, never
//      green for an unmeasured balance.
//  - Per pool: source and confidence, update time, and what it applies to
//    (shared by the account, or a named model).
//  - No key, not even masked: the "Same account as …" note is what tells
//    accounts apart, and a key fragment is not something this sheet needs.
//  - Pull to refresh / toolbar refresh use the store's forced refresh:
//    single flight, Retry-After and the 30 s debounce still apply.
//

import SwiftUI

/// Identifiable wrapper for `.sheet(item:)` hosts that open this sheet.
struct QuotaSheetTarget: Identifiable, Equatable { let id: String }

struct QuotaDetailSheet: View {
    let instanceId: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var quota = QuotaStore.shared
    @State private var blockedMessage: String?
    /// [T-quota-console-links] The vendor usage page, in the in-app browser.
    @State private var consoleURL: URL?

    var body: some View {
        NavigationStack {
            List {
                if let instance = ProviderConfigStore.shared.instance(for: instanceId) {
                    let display = quota.display(for: instance)
                    if case .pools = display {} else if let url = QuotaConsoleLink.url(for: QuotaStore.descriptor(for: instance)) {
                        Section {
                            QuotaConsoleLinkRow(url: url) { consoleURL = url }
                                .codyGroupedRow()
                        }
                    }
                    switch display {
                    case .pools(let sid):
                        accountSection(sid)
                        ForEach(quota.pools(of: sid)) { pool in
                            poolSection(pool)
                        }
                        Section {
                            EmptyView()
                        } footer: {
                            Text("Figures come from the provider. Cody's own token counts are not included.")
                        }
                    case .loading:
                        Section {
                            HStack(spacing: CodySpacing.sm) {
                                ProgressView().controlSize(.small)
                                Text("Checking balance…")
                                    .font(CodyTypography.bodyMedium)
                                    .foregroundStyle(CodyColors.textSecondary)
                            }
                            .codyGroupedRow()
                        }
                    case .unsupported(let reason):
                        Section {
                            Text(ProviderQuotaSection.message(for: reason))
                                .font(CodyTypography.bodyMedium)
                                .foregroundStyle(CodyColors.textSecondary)
                                .codyGroupedRow()
                        }
                    case .failed(let err):
                        Section {
                            Text(ProviderQuotaSection.message(for: err))
                                .font(CodyTypography.bodyMedium)
                                .foregroundStyle(CodyColors.statusWarningText)
                                .codyGroupedRow()
                        }
                    case .empty:
                        Section {
                            Text("The provider reported no balance or quota for this key.")
                                .font(CodyTypography.bodyMedium)
                                .foregroundStyle(CodyColors.textSecondary)
                                .codyGroupedRow()
                        }
                    case .hidden:
                        Section {
                            Text("Add an API key to see the balance.")
                                .font(CodyTypography.bodyMedium)
                                .foregroundStyle(CodyColors.textSecondary)
                                .codyGroupedRow()
                        }
                    }
                }
            }
            .codyGroupedListCanvas()
            .refreshable { await refresh() }
            .sheet(item: $consoleURL) { url in
                CodyLinkPreviewView(url: url, browserPool: nil)
            }
            .navigationTitle(ProviderConfigStore.shared.instance(for: instanceId)?.label ?? String(localized: "Quota"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if quota.isRefreshing(instanceId) {
                        ProgressView()
                    } else {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel(Text("Refresh quota"))
                    }
                }
            }
        }
        .quotaWatch(instanceId: instanceId, reason: "detailSheet")
    }

    // MARK: - Sections

    @ViewBuilder
    private func accountSection(_ sid: QuotaSubjectID) -> some View {
        let subject = quota.subject(sid)
        Section {
            if let instance = ProviderConfigStore.shared.instance(for: instanceId),
               let detection = quota.relayDetection(for: instance), detection.found {
                LabeledContent(String(localized: "Relay type")) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(detection.text)
                            .foregroundStyle(CodyColors.textPrimary)
                        Text(String(format: String(localized: "detected %@"), ProviderQuotaSection.relative(detection.at)))
                            .font(CodyTypography.labelSmall.monospacedDigit())
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
                .codyGroupedRow()
            }
            if let refreshed = subject?.lastRefresh?.succeededAt {
                LabeledContent(String(localized: "Last checked")) {
                    Text(Self.stamp(refreshed))
                        .font(CodyTypography.bodyMedium.monospacedDigit())
                        .foregroundStyle(CodyColors.textSecondary)
                }
                .codyGroupedRow()
            }
            let sharing = quota.sharingInstanceIds(for: instanceId)
                .compactMap { ProviderConfigStore.shared.instance(for: $0)?.label }
            if !sharing.isEmpty {
                Text(String(format: String(localized: "Same account as “%@” — the same balance, don't add them up"),
                            sharing.joined(separator: "”, “")))
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .codyGroupedRow()
            }
            if let err = subject?.lastRefresh?.error {
                Text(String(format: String(localized: "Last refresh failed: %@"), ProviderQuotaSection.message(for: err)))
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.statusWarningText)
                    .codyGroupedRow()
            }
            if let blockedMessage {
                Text(blockedMessage)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .codyGroupedRow()
            }
            if let instance = ProviderConfigStore.shared.instance(for: instanceId),
               let url = QuotaConsoleLink.url(for: QuotaStore.descriptor(for: instance)) {
                QuotaConsoleLinkRow(url: url) { consoleURL = url }
                    .codyGroupedRow()
            }
        } header: {
            Text("Account")
                .codySectionHeaderText()
        }
    }

    @ViewBuilder
    private func poolSection(_ pool: QuotaPool) -> some View {
        let status = quota.poolStatus(pool)
        let scopes = quota.bindings.filter { $0.poolKey == pool.id }
        Section {
            QuotaPoolRow(pool: pool, status: status, detailed: true)
                .codyGroupedRow()
            LabeledContent(String(localized: "Source")) {
                Text(Self.sourceText(pool.provenance))
                    .foregroundStyle(CodyColors.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .codyGroupedRow()
            LabeledContent(String(localized: "Updated")) {
                Text(Self.stamp(pool.observedAt))
                    .font(CodyTypography.bodyMedium.monospacedDigit())
                    .foregroundStyle(CodyColors.textSecondary)
            }
            .codyGroupedRow()
            ForEach(Array(scopes.enumerated()), id: \.offset) { _, binding in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.scopeText(binding.target))
                            .foregroundStyle(CodyColors.textPrimary)
                        if binding.evidence == .assumedSubjectWide {
                            Text("The provider didn't state the scope; treated as shared by the account.")
                                .font(CodyTypography.labelSmall)
                                .foregroundStyle(CodyColors.textSecondary)
                        }
                    }
                } icon: {
                    // [T-quota-badge-ui] Settings-row badge style (filled glyph on a
                    // coloured circle), the shared BackupActionIcon.
                    Self.scopeIcon(binding.target)
                }
                .font(CodyTypography.bodySmall)
                .codyGroupedRow()
            }
        } header: {
            Text(Self.kindName(pool.kind))
                .codySectionHeaderText()
        }
    }

    // MARK: - Actions

    private func refresh() async {
        let result = await quota.refresh(instanceId: instanceId, forced: true, reason: "detailSheet")
        switch result {
        case .blocked(.serverCooldown(let until)):
            blockedMessage = String(format: String(localized: "The provider asked to wait until %@."),
                                    until.formatted(date: .omitted, time: .shortened))
        case .blocked(.forcedDebounce):
            blockedMessage = String(localized: "Just refreshed — try again in a few seconds.")
        default:
            blockedMessage = nil
        }
    }

    // MARK: - Text

    static func stamp(_ date: Date) -> String {
        "\(date.formatted(date: .abbreviated, time: .shortened)) · \(ProviderQuotaSection.relative(date))"
    }

    static func sourceText(_ p: QuotaProvenance) -> String {
        "\(QuotaFormat.source(p.source)) · \(confidenceText(p.confidence))"
    }

    static func confidenceText(_ c: QuotaConfidence) -> String {
        switch c {
        case .documented: return String(localized: "Documented")
        case .observedClient: return String(localized: "Observed, undocumented")
        case .unverified: return String(localized: "Unverified")
        case .thirdParty: return String(localized: "Reported by a relay")
        case .userDeclared: return String(localized: "Set by you")
        }
    }

    static func scopeText(_ t: QuotaPoolBinding.Target) -> String {
        switch t {
        case .subject: return String(localized: "Shared by all models on this account")
        case .model(let key): return String(format: String(localized: "Model: %@"), key)
        case .modelFamily(let pattern): return String(format: String(localized: "Models matching %@"), pattern)
        case .product(let name): return String(format: String(localized: "Product: %@"), name)
        }
    }

    /// Shared account = blue people, a model or family = purple chip, a product =
    /// indigo box. Same 21 pt circle as every Settings row icon.
    static func scopeIcon(_ t: QuotaPoolBinding.Target) -> BackupActionIcon {
        switch t {
        case .subject: return BackupActionIcon(systemName: "person.2.fill", tint: .blue)
        case .model, .modelFamily: return BackupActionIcon(systemName: "cpu.fill", tint: .purple)
        case .product: return BackupActionIcon(systemName: "shippingbox.fill", tint: .indigo)
        }
    }

    static func kindName(_ k: QuotaPool.Kind) -> String {
        switch k {
        case .prepaidBalance: return String(localized: "Prepaid balance")
        case .spendCap: return String(localized: "Spend limit")
        case .allowance: return String(localized: "Allowance")
        case .usageWindow: return String(localized: "Usage limit")
        case .rateLimit: return String(localized: "Rate limit")
        }
    }
}
