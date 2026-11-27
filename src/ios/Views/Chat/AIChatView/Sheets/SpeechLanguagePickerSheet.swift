//
//  SpeechLanguagePickerSheet.swift
//  Cody - chat page (AIChatView)
//
//  Picker for the speech recognition language, opened from the composer's
//  language badge.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI

// MARK: - Speech Language Picker Sheet

private struct SpeechLanguagePickerSheet: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLocales: [Locale] {
        if searchText.isEmpty { return speechManager.availableLocales }
        let query = searchText.lowercased()
        return speechManager.availableLocales.filter { loc in
            let name = speechManager.displayName(for: loc).lowercased()
            let id = loc.identifier.lowercased()
            return name.contains(query) || id.contains(query)
        }
    }

    /// Indices where the preferred/non-preferred boundary lies for section headers.
    private var preferredCodes: Set<String> {
        Set(Locale.preferredLanguages.map { Locale(identifier: $0).language.languageCode?.identifier ?? "" })
    }

    var body: some View {
        NavigationStack {
            List {
                let preferred = filteredLocales.filter { preferredCodes.contains($0.language.languageCode?.identifier ?? "") }
                let others = filteredLocales.filter { !preferredCodes.contains($0.language.languageCode?.identifier ?? "") }

                if !preferred.isEmpty {
                    Section {
                        ForEach(preferred, id: \.identifier) { loc in
                            languageRow(loc)
                        }
                    } header: {
                        Text(AppLocalized("Preferred", comment: "Section header for preferred speech languages"))
                            .font(CodyTypography.sectionHeader)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }

                if !others.isEmpty {
                    Section {
                        ForEach(others, id: \.identifier) { loc in
                            languageRow(loc)
                        }
                    } header: {
                        Text(AppLocalized("All Languages", comment: "Section header for all speech languages"))
                            .font(CodyTypography.sectionHeader)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgGrouped)
            .searchable(text: $searchText, prompt: Text("Search Languages", comment: "Search field placeholder for speech language picker"))
            .navigationTitle(Text("Voice Language", comment: "Navigation title for speech language picker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalized("Done", comment: "Dismiss speech language picker")) {
                        dismiss()
                    }
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func languageRow(_ loc: Locale) -> some View {
        let isSelected = loc.identifier == speechManager.locale.identifier
        return Button {
            speechManager.setLanguage(loc)
            dismiss()
        } label: {
            HStack(spacing: CodySpacing.md) {
                VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                    Text(speechManager.displayName(for: loc))
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                    Text(loc.identifier)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(CodyTypography.labelLarge)
                        .foregroundStyle(CodyColors.iconPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: CodyControlHeight.standard)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(CodyColors.bgGroupedSurface)
        .listRowSeparatorTint(CodyColors.separator)
    }
}
