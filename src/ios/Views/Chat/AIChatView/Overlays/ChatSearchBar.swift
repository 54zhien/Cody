//
//  ChatSearchBar.swift
//  Cody - chat page (AIChatView)
//
//  [T-in-chat-search] The bar "Search in Chat" opens under the navigation
//  bar: query field, "3/12" counter, previous (older) / next (newer), Done.
//  Mounted in AIChatView's `topBanners`, so the list's top inset already
//  makes room for it. Observes only the search controller - typing here
//  never re-renders the chat page.
//
//  Keys: Return = next result, Shift-Return = previous.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI
import UIKit

struct ChatSearchBar: View {
    @ObservedObject var search: ChatSearchController
    /// Called after Done: the page restores its composer.
    var onDone: () -> Void
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var hasQuery: Bool { !search.normalizedQuery.isEmpty }
    private var hasResults: Bool { search.matchCount > 0 }

    var body: some View {
        let fieldShape = RoundedRectangle(cornerRadius: CodyRadius.pill, style: .continuous)
        HStack(spacing: CodySpacing.xsPlus) {
            HStack(spacing: CodySpacing.xsPlus) {
                Image(systemName: "magnifyingglass")
                    .font(CodyTypography.bodyMedium.weight(.medium))
                    .foregroundStyle(CodyColors.iconSecondary)
                    .accessibilityHidden(true)
                TextField(AppLocalized("Search this chat"), text: $search.query)
                    .textFieldStyle(.plain)
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textPrimary)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)
                    .onSubmit {
                        search.next()
                        // Return must not dismiss the keyboard: the user is
                        // stepping through results.
                        fieldFocused = true
                    }
                    .accessibilityIdentifier("chatSearchField")
                if hasQuery {
                    counter
                    Button {
                        search.query = ""
                        fieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(CodyTypography.bodyMedium)
                            .foregroundStyle(CodyColors.iconTertiary)
                            .frame(width: CodySpacing.xxl, height: CodyControlHeight.compact)
                            .contentShape(Rectangle().inset(by: -CodySpacing.xs))
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityLabel(AppLocalized("Clear"))
                }
            }
            .padding(.horizontal, CodySpacing.md)
            .frame(height: CodyControlHeight.compact)
            .background(fieldShape.fill(CodyColors.bgTertiary))
            .overlay {
                fieldShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                navButton(systemName: "chevron.up", label: AppLocalized("Previous Result")) { search.previous() }
                    .keyboardShortcut(.return, modifiers: .shift)
                    .accessibilityIdentifier("chatSearchPrevious")
                navButton(systemName: "chevron.down", label: AppLocalized("Next Result")) { search.next() }
                    .accessibilityIdentifier("chatSearchNext")
            }

            Button {
                fieldFocused = false
                search.deactivate()
                onDone()
            } label: {
                Text(AppLocalized("Done"))
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                    .padding(.horizontal, CodySpacing.sm)
                    .frame(minWidth: CodyControlHeight.standard, minHeight: CodyControlHeight.standard)
                    .contentShape(Capsule())
            }
            .buttonStyle(CodyPressableButtonStyle())
            .accessibilityIdentifier("chatSearchDone")
        }
        .padding(.horizontal, CodySpacing.md)
        .padding(.vertical, CodySpacing.xsPlus)
        .background {
            if reduceTransparency {
                CodyColors.bgCanvasSubtle
            } else {
                Rectangle().fill(.bar)
            }
        }
        .overlay(alignment: .bottom) {
            CodyColors.separator.frame(height: CodySpacing.px)
        }
        .overlay(alignment: .bottom) { noticeView.offset(y: CodySpacing.s36) }
        .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: hasQuery)
        .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: search.notice != nil)
        .onAppear { fieldFocused = true }
        .onChange(of: search.focusRequest) { _ in fieldFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chatSearchBar")
    }

    @ViewBuilder
    private var counter: some View {
        if search.isSearching && !hasResults {
            ProgressView()
                .controlSize(.small)
                .frame(width: CodySpacing.xl)
        } else if hasResults {
            Text(verbatim: ChatSearchNavigation.counterText(index: search.currentIndex, count: search.matchCount,
                                                            truncated: search.isTruncated))
                .font(CodyTypography.bodySmall.monospacedDigit())
                .foregroundStyle(CodyColors.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(search.currentIndex.map { AppLocalized("Result \($0 + 1) of \(search.matchCount)") } ?? "")
                .accessibilityIdentifier("chatSearchCounter")
        } else {
            Text(AppLocalized("No results"))
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("chatSearchCounter")
        }
    }

    private func navButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(CodyTypography.labelLarge)
                .foregroundStyle(hasResults ? CodyColors.iconPrimary : CodyColors.iconTertiary)
                .frame(minWidth: CodyControlHeight.standard, minHeight: CodyControlHeight.standard)
                .contentShape(Circle())
        }
        .buttonStyle(CodyPressableButtonStyle())
        .disabled(!hasResults)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = search.notice {
            Text(ChatSearchController.noticeText(notice))
                .font(CodyTypography.labelMedium)
                .foregroundStyle(CodyColors.interactivePrimaryLabel)
                .padding(.horizontal, CodySpacing.md)
                .padding(.vertical, CodySpacing.xsPlus)
                .background(CodyColors.interactivePrimaryBg, in: Capsule())
                .transition(reduceMotion ? .identity : .opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// [T-in-chat-search] The chat page's side of search, kept out of AIChatView's
/// body: offers "Search in Chat" to the long-press menus while this page shows
/// the conversation, mirrors whether the bar is open into `isActive` (which
/// shows the bar and hides the composer), and closes the bar when the page
/// goes away.
struct ChatSearchHostModifier: ViewModifier {
    let search: ChatSearchController
    @Binding var isActive: Bool
    @Binding var inputFocused: Bool
    /// This page's claim on the opener (see `openSearchOwner`).
    @State private var ownerId = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                search.highlights.openSearchOwner = ownerId
                search.highlights.openSearch = { [weak search] prefill in
                    search?.activate(prefill: prefill)
                }
            }
            .onDisappear {
                // A page re-created for the same conversation may already have
                // taken over (its onAppear can run before this onDisappear).
                guard search.highlights.openSearchOwner == ownerId else { return }
                search.deactivate()
                search.highlights.openSearch = nil
                search.highlights.openSearchOwner = nil
            }
            .onReceive(search.$isActive.removeDuplicates()) { active in
                guard active != isActive else { return }
                // The composer is hidden while searching: two text fields
                // would fight over the keyboard.
                if active { inputFocused = false }
                isActive = active
            }
    }
}

/// [T-in-chat-search] Hides the composer while the search bar is open. It
/// keeps its place in the layout (only fades out and stops taking touches), so
/// the list's bottom inset - and with it the scroll position - is the same
/// before, during and after a search.
struct ChatSearchComposerHider: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}
