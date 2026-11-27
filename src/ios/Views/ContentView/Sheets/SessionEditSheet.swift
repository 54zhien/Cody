//
//  SessionEditSheet.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  Edit a session's title and category; SpinningRing is shared with the rows
//  and section headers.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Session Edit Sheet

struct SessionEditSheet: View {
    let session: ChatSession
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editTitle: String = ""
    @State private var editCategory: String = ""
    @State private var isRegenerating = false

    private static let categories: [(key: String, label: String, icon: String, tint: CodyCategoryTint)] = [
        ("code",         "Code",         "terminal.fill",               .orange),
        ("writing",      "Writing",      "doc.text.fill",               .blue),
        ("research",     "Research",     "globe.americas.fill",         .green),
        ("analysis",     "Analysis",     "chart.pie.fill",              .purple),
        ("creative",     "Creative",     "paintbrush.pointed.fill",     .red),
        ("chat",         "Chat",         "bubble.left.fill",            .green),
        ("math",         "Math",         "number.circle.fill",          .purple),
        ("translation",  "Translation",  "character.bubble",            .blue),
        ("health",       "Health",       "heart.fill",                  .red),
        ("finance",      "Finance",      "banknote.fill",               .green),
        ("travel",       "Travel",       "map.fill",                    .orange),
        ("education",    "Education",    "book.closed.fill",            .blue),
        ("design",       "Design",       "paintpalette.fill",           .red),
        ("productivity", "Productivity", "calendar.badge.checkmark",    .orange),
        ("support",      "Support",      "gearshape.fill",              .orange),
        ("other",        "Other",        "square.grid.2x2.fill",        .neutral),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Session title", text: $editTitle)
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                        .listRowBackground(CodyColors.bgGroupedSurface)
                        .listRowSeparatorTint(CodyColors.separator)
                } header: {
                    Text("Title")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: CodySpacing.md)], spacing: CodySpacing.md) {
                        ForEach(Self.categories, id: \.key) { cat in
                            let isSelected = editCategory == cat.key
                            Button {
                                editCategory = cat.key
                            } label: {
                                VStack(spacing: CodySpacing.xsPlus) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(cat.tint.color)
                                        .frame(width: CodyControlHeight.standard, height: CodyControlHeight.standard)
                                        .background(
                                            Circle()
                                                .fill(isSelected ? cat.tint.color.opacity(0.16) : CodyColors.bgListIcon)
                                        )
                                        .overlay {
                                            Circle()
                                                .strokeBorder(
                                                    isSelected ? cat.tint.color : CodyColors.borderListIcon,
                                                    lineWidth: isSelected ? 1.5 : CodySpacing.px
                                                )
                                                .allowsHitTesting(false)
                                        }
                                        .accessibilityHidden(true)
                                    Text(LocalizedStringKey(cat.label))
                                        .font(isSelected ? CodyTypography.labelSmall.weight(.semibold) : CodyTypography.labelSmall)
                                        .foregroundStyle(isSelected ? CodyColors.textPrimary : CodyColors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(CodyPressableButtonStyle())
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, CodySpacing.sm)
                    .listRowBackground(CodyColors.bgGroupedSurface)
                    .listRowSeparatorTint(CodyColors.separator)
                } header: {
                    Text("Category")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Section {
                    Button {
                        regenerate()
                    } label: {
                        HStack(spacing: CodySpacing.sm) {
                            if isRegenerating {
                                SpinningRing(color: CodyColors.iconPrimary)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .accessibilityHidden(true)
                            }
                            Text("Regenerate Title")
                        }
                        .font(CodyTypography.labelLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard, alignment: .center)
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .disabled(isRegenerating)
                    .listRowBackground(CodyColors.bgGroupedSurface)
                    .listRowSeparatorTint(CodyColors.separator)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgGrouped)
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CodyColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        onSave(title, editCategory.isEmpty ? nil : editCategory)
                    }
                    .bold()
                    .foregroundStyle(CodyColors.textPrimary)
                    .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                editTitle = session.title ?? ""
                editCategory = session.category ?? ""
            }
        }
    }

    private func regenerate() {
        guard !isRegenerating else { return }
        isRegenerating = true
        Task { @MainActor in
            defer { isRegenerating = false }
            do {
                try await AIChatViewModel.regenerateSessionTitle(sessionId: session.id)
                if let updated = await ChatStore.shared.getSession(session.id) {
                    if let title = updated.title { editTitle = title }
                    editCategory = updated.category ?? editCategory
                }
            } catch {
                AppLogger(category: "RegenerateTitle").error(
                    "session=\(session.id) failed: \(error.localizedDescription) — \(String(describing: error))"
                )
            }
        }
    }
}

/// A self-contained spinning arc that uses TimelineView to avoid
/// stacking animations on repeated onAppear calls.
struct SpinningRing: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        } else {
            TimelineView(.animation) { timeline in
                let angle = timeline.date.timeIntervalSinceReferenceDate.remainder(dividingBy: 1.0) * 360
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
        }
    }
}
