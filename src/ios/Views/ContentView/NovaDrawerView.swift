import SwiftUI

struct NovaDrawerView<Header: View, History: View, Profile: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let history: () -> History
    @ViewBuilder let profile: () -> Profile

    var body: some View {
        VStack(spacing: 0) {
            header()
            history()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            profile()
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(CodyColors.borderLight)
                        .frame(height: CodySpacing.px)
                        .allowsHitTesting(false)
                }
        }
        .background(CodyColors.bgCanvas.ignoresSafeArea())
    }
}

extension ContentView {
    var novaDrawer: some View {
        NovaDrawerView {
            if isSelecting {
                novaSelectionHeader
            } else {
                VStack(spacing: CodySpacing.sm) {
                    novaSearchHeader
                    VStack(spacing: 0) {
                        novaDrawerDestination("New Chat", icon: "square.and.pencil", tint: .neutral,
                                              action: startNewNovaChat)
                        novaDrawerDestination("Explore & Tools", icon: "square.grid.2x2", tint: .blue) {
                            selectNovaTab(.explore)
                        }
                        novaDrawerDestination("Files", icon: "folder", tint: .neutral) {
                            selectNovaTab(.files)
                        }
                    }
                }
                .padding(.horizontal, CodySpacing.md)
                .padding(.top, CodySpacing.sm)
                .padding(.bottom, CodySpacing.xs)
            }
        } history: {
            sessionList(useNavigationLinks: true)
        } profile: {
            novaProfileBar
        }
        .accessibilityAction(.escape) { closeNovaDrawer() }
        .modifier(NovaOnboardingSheets(
            showAddProvider: $showAddProvider,
            showSelectModels: $showSelectModels,
            showRestoreBackup: $showRestoreBackup
        ))
    }

    private var novaSearchHeader: some View {
        HStack(spacing: CodySpacing.sm) {
            HStack(spacing: CodySpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CodyColors.iconSecondary)
                    .accessibilityHidden(true)
                TextField("Search chats", text: $searchText)
                    .font(CodyTypography.bodyMedium)
                    .foregroundStyle(CodyColors.textPrimary)
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onChange(of: searchText) { _ in scheduleSearch() }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        scheduleSearch()
                    } label: {
                        Label("Clear search", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(CodyColors.iconSecondary)
                            .frame(minWidth: CodyControlHeight.standard, minHeight: CodyControlHeight.standard)
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                }
            }
            .padding(.leading, CodySpacing.md)
            .padding(.trailing, searchText.isEmpty ? CodySpacing.md : 0)
            .frame(minHeight: CodyControlHeight.standard)
            .background(CodyColors.interactiveSecondaryBg, in: Capsule())

            novaDrawerIcon("New Chat", icon: "square.and.pencil", action: startNewNovaChat)
                .background(CodyColors.interactiveSecondaryBg, in: Circle())
        }
    }

    private var novaSelectionHeader: some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            Text(selectedIds.isEmpty ? "Select Sessions" : "\(selectedIds.count) Selected")
                .font(CodyTypography.titleSmall)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Cancel") {
                    isSelecting = false
                    selectedIds.removeAll()
                }
                Spacer(minLength: CodySpacing.sm)
                Button(selectedIds.count == sessions.count ? "Deselect All" : "Select All") {
                    selectedIds = selectedIds.count == sessions.count ? [] : Set(sessions.map(\.id))
                }
            }
            .font(CodyTypography.labelLarge)
            .frame(minHeight: CodyControlHeight.standard)
        }
        .padding(.horizontal, CodySpacing.lg)
        .padding(.top, CodySpacing.sm)
    }

    private func novaDrawerDestination(
        _ title: LocalizedStringKey,
        icon: String,
        tint: CodyCategoryTint,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CodySpacing.sm) {
                CodyListIconBadge(systemImage: icon, tint: tint)
                Text(title)
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
            }
            .padding(.horizontal, CodySpacing.xs)
            .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodyPressableButtonStyle())
    }

    var novaSplitDestinations: some View {
        HStack(spacing: CodySpacing.sm) {
            ForEach(CodyNovaTab.allCases) { tab in
                Button {
                    selectNovaTab(tab)
                } label: {
                    Label(tab.title, systemImage: tab.iconName)
                        .font(CodyTypography.labelMedium)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CodyColors.textPrimary)
                        .padding(.horizontal, CodySpacing.sm)
                        .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard)
                        .background(novaTab == tab ? CodyColors.interactiveSecondaryBg : .clear,
                                    in: RoundedRectangle(cornerRadius: CodyRadius.control))
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityAddTraits(novaTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, CodySpacing.sm)
        .padding(.bottom, CodySpacing.xs)
        .background(CodyColors.bgCanvas)
    }

    var novaSetupCard: some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            Text("Set up Cody")
                .font(CodyTypography.titleSmall)
                .accessibilityAddTraits(.isHeader)
            Text("Connect a provider and choose models to start chatting.")
                .font(CodyTypography.bodyMedium)
                .foregroundStyle(CodyColors.textSecondary)
            if providerStore.instances.isEmpty {
                novaDrawerDestination("Add a Provider", icon: "plus", tint: .blue) { showAddProvider = true }
            } else {
                novaDrawerDestination("Select Models", icon: "cpu", tint: .blue) { showSelectModels = true }
            }
            novaDrawerDestination("Restore Backup", icon: "clock.arrow.circlepath", tint: .neutral) {
                showRestoreBackup = true
            }
        }
        .foregroundStyle(CodyColors.textPrimary)
        .padding(CodySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodyColors.interactiveSecondaryBg,
                    in: RoundedRectangle(cornerRadius: CodyRadius.surface))
    }

    private var canOpenNovaSync: Bool {
        if #available(iOS 17.0, *) { return SyncV2Bootstrap.isEnabled }
        return false
    }

    private var novaProfileBar: some View {
        HStack(spacing: CodySpacing.xxs) {
            Button { openNovaToolSheet(.settings) } label: {
                HStack(spacing: CodySpacing.sm) {
                    SoulIconView(icon: SoulStore.cachedMetadata.icon, size: CodySpacing.xxl)
                        .frame(width: CodyControlHeight.compact, height: CodyControlHeight.compact)
                        .background(CodyColors.interactiveSecondaryBg, in: Circle())
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    Text(soulName)
                        .font(CodyTypography.titleSmall)
                        .lineLimit(1)
                    if canOpenNovaSync {
                        titleSyncIndicator(for: migrationSubtitle)
                    }
                }
                .foregroundStyle(CodyColors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CodyPressableButtonStyle())
            .accessibilityHint("Opens Settings")

            novaDrawerIcon("Settings", icon: "gearshape") { openNovaToolSheet(.settings) }
            novaDrawerIcon("Linux Terminal", icon: "terminal") {
                closeNovaDrawer()
                showTerminal = true
            }
            Menu {
                if canOpenNovaSync {
                    Button { openNovaToolSheet(.syncMigrationDetail) } label: {
                        Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if hasAlarms {
                    Button {
                        closeNovaDrawer()
                        showAlarmList = true
                    } label: {
                        Label("Alarms", systemImage: "alarm")
                    }
                }
                Button { openNovaToolSheet(.rootfsManagement) } label: {
                    Label("Rootfs Management", systemImage: "externaldrive")
                }
                Button { openNovaToolSheet(.browserManagement) } label: {
                    Label("Browser Settings", systemImage: "globe.badge.chevron.backward")
                }
                #if DEBUG
                Button(action: toggleDebugScreenAwake) {
                    Label("Keep Screen Awake", systemImage: keepScreenAwake ? "checkmark.circle.fill" : "sun.max")
                }
                #endif
            } label: {
                novaDrawerIconLabel("More tools", icon: "ellipsis")
            }
        }
        .padding(.horizontal, CodySpacing.md)
        .padding(.vertical, CodySpacing.xs)
    }

    private func openNovaToolSheet(_ sheet: ToolSheet) {
        closeNovaDrawer()
        activeToolSheet = sheet
    }

    private func novaDrawerIcon(_ label: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { novaDrawerIconLabel(label, icon: icon) }
            .buttonStyle(CodyPressableButtonStyle())
    }

    private func novaDrawerIconLabel(_ label: LocalizedStringKey, icon: String) -> some View {
        Label(label, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.body.weight(.medium))
            .foregroundStyle(CodyColors.iconPrimary)
            .frame(width: CodyControlHeight.standard, height: CodyControlHeight.standard)
            .contentShape(Rectangle())
    }
}

private struct NovaOnboardingSheets: ViewModifier {
    @Binding var showAddProvider: Bool
    @Binding var showSelectModels: Bool
    @Binding var showRestoreBackup: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddProvider) {
                NavigationStack { AddProviderView() }
            }
            .sheet(isPresented: $showSelectModels) {
                NavigationStack { OnboardingModelSelectionView() }
            }
            .sheet(isPresented: $showRestoreBackup) {
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
}
