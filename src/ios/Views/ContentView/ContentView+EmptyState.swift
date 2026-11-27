//
//  ContentView+EmptyState.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  ContentView, empty state: the first-run checklist (add a provider, select
//  models, or restore a backup). Its sheet flags and the provider store are
//  stored in ContentView.swift.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

extension ContentView {
    // MARK: - Empty State

    /// [T-onboarding-hide-fab] Whether the floating New Chat / Search buttons
    /// stay hidden because the first-run checklist owns the screen. The two are
    /// mounted independently (checklist = list overlay, buttons = bottom safe
    /// area inset), so without this the New Chat button floated over steps 1-2
    /// before any provider or model existed - offering a chat that cannot run.
    /// Hidden only until models are selected: from then on step 3's subtitle
    /// ("Tap the button below to begin") points at that very button, and a
    /// returning user with no chats lands on this same screen.
    /// `showSearchBar` keeps an open search field from vanishing under it.
    /// Not gated on `didInitialLoad`: the provider config is read synchronously
    /// in ProviderConfigStore.init, so a set-up user never matches, and a first
    /// launch no longer flashes the buttons while the (empty) list loads.
    func hidesFABForOnboarding(listIsEmpty: Bool) -> Bool {
        listIsEmpty && !showSearchBar && providerStore.modelGroups.isEmpty
    }

    var emptyState: some View {
        let hasProviders = !providerStore.instances.isEmpty
        let hasGroups = !providerStore.modelGroups.isEmpty
        let heroShape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)

        return VStack(spacing: CodySpacing.xxxl) {
            Spacer()
            // App icon / hero
            Image(systemName: "sparkles")
                .font(.title2.weight(.medium))
                .foregroundStyle(CodyColors.iconPrimary)
                .frame(width: CodySpacing.s56, height: CodySpacing.s56)
                .background(heroShape.fill(CodyColors.bgElevatedPrimary))
                .clipShape(heroShape)
                .overlay {
                    heroShape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                        .allowsHitTesting(false)
                }
                .accessibilityHidden(true)

            VStack(spacing: CodySpacing.sm) {
                Text("Welcome to Cody")
                    .font(CodyTypography.headlineSmall)
                    .foregroundStyle(CodyColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Your first On-Device Agent is almost ready.")
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Setup steps
            VStack(spacing: CodySpacing.lg) {
                // Step 1 – Add Provider
                setupStep(
                    number: 1,
                    title: "Add a Provider",
                    subtitle: hasProviders ? "Done" : "Configure an API key or sign in with OAuth",
                    isDone: hasProviders
                ) {
                    if !hasProviders {
                        showAddProvider = true
                    }
                }

                // Step 2 – Select Models
                setupStep(
                    number: 2,
                    title: "Select Models",
                    subtitle: hasGroups ? "Done" : (hasProviders ? "Choose the models you want to use" : "Complete step 1 first"),
                    isDone: hasGroups
                ) {
                    if hasProviders && !hasGroups {
                        showSelectModels = true
                    }
                }

                // Step 3 – Start chatting
                setupStep(
                    number: 3,
                    title: "Start a Conversation",
                    subtitle: hasGroups ? "Tap the button below to begin" : "Complete step 2 first",
                    isDone: false
                ) {
                    if hasGroups {
                        // [T-nav-ghost-row-link] From the home list: replace, never append.
                        switchToSession(Self.makeNewSessionId())
                    }
                }
            }
            .padding(.horizontal, CodySpacing.sm)
            .frame(maxWidth: 400)

            Spacer()

            // [T-onboarding-restore-link] A side route for someone moving from
            // another device: kept to a footnote link (not a fourth card) so it
            // does not compete with the three steps. Shown only until models
            // are selected — after that this empty state also greets returning
            // users with no chats, for whom Settings → Backup & Restore is the
            // path. Restore merges, so it is safe after step 1 as well.
            //
            // [T-onboarding-restore-link-bottom] Pinned to the bottom, below
            // the second Spacer, rather than tucked under step 3: a footnote
            // reads as a footer, and the steps keep the centre to themselves.
            // The overlay inherits the list's safe area, so this sits above the
            // Home Indicator; the extra bottom padding keeps it clear of the
            // indicator's swipe zone as well.
            if !hasGroups {
                Button {
                    showRestoreBackup = true
                } label: {
                    Label("Have a backup? Restore from it", systemImage: "clock.arrow.circlepath")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                        .padding(.horizontal, CodySpacing.md)
                        .frame(minHeight: CodyControlHeight.standard)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .padding(.bottom, CodySpacing.sm)
                .accessibilityIdentifier("onboarding.restoreBackup")
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, CodySpacing.xxxl)
        .sheet(isPresented: $showAddProvider) {
            NavigationStack {
                AddProviderView()
            }
        }
        .sheet(isPresented: $showSelectModels) {
            NavigationStack {
                OnboardingModelSelectionView()
            }
        }
        .sheet(isPresented: $showRestoreBackup) {
            // Same presentation as opening a .codybak from Files: straight to
            // the Restore tab. Not auto-dismissed on success — the result
            // report is worth reading; the steps above refresh on their own
            // (restore reloads ProviderConfigStore and the session list).
            NavigationStack {
                BackupAndRestoreView(initialTab: .restore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showRestoreBackup = false }
                        }
                    }
            }
        }
    }

    // title/subtitle must stay LocalizedStringKey, not String. A string literal at
    // the call site localizes fine on its own, but routing it through a String
    // parameter erases that: `Text(String)` stores the value verbatim and never
    // consults the string table, so these steps rendered English even though
    // Localizable.xcstrings has all 8 locales for these keys. Typing the parameter
    // as LocalizedStringKey keeps the literals (both branches of the `isDone`
    // ternaries included) resolving as keys.
    private func setupStep(
        number: Int,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isDone: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        return Button(action: action) {
            HStack(spacing: CodySpacing.mdPlus) {
                // Step indicator
                ZStack {
                    Circle()
                        .fill(isDone ? CodyColors.statusSuccessBg : CodyColors.interactivePrimaryBg)
                        .frame(width: CodyControlHeight.sm, height: CodyControlHeight.sm)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(CodyTypography.labelLarge.weight(.bold))
                            .foregroundStyle(CodyColors.statusSuccessText)
                            .accessibilityHidden(true)
                    } else {
                        Text("\(number)")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    }
                }

                VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                    Text(title)
                        .font(CodyTypography.titleSmall)
                        .foregroundStyle(isDone ? CodyColors.textSecondary : CodyColors.textPrimary)
                    Text(subtitle)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Spacer()

                if !isDone {
                    Image(systemName: "chevron.right")
                        .font(CodyTypography.labelMedium)
                        .foregroundStyle(CodyColors.iconDisclosure)
                        .accessibilityHidden(true)
                }
            }
            .padding(CodySpacing.mdPlus)
            .modifier(CodySurfaceModifier(radius: CodyRadius.surface))
            .contentShape(cardShape)
        }
        .buttonStyle(CodyPressableButtonStyle())
        .disabled(isDone)
    }
}
