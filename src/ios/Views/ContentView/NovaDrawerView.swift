import SwiftUI

struct NovaDrawerView<Header: View, History: View, Actions: View>: View {
    let showsActions: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let history: () -> History
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            header()
            history()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsActions { Color.clear.frame(height: 60) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if showsActions {
                actions()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background {
                        LinearGradient(
                            colors: [.clear, CodyColors.bgCanvas.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
            }
        }
    }
}

extension ContentView {
    private var novaPrimaryDestinations: [CodyNovaDestination] {
        [.home] + novaTabStore.pinnedTools.map { .tool($0) } + [.more]
    }

    var novaDrawer: some View {
        NovaDrawerView(showsActions: !isSelecting) {
            Group {
                if isSelecting {
                    novaSelectionHeader
                } else if showSearchBar {
                    novaSearchHeader
                } else {
                    VStack(spacing: 0) {
                        ForEach(novaPrimaryDestinations) { destination in
                            novaDrawerDestination(destination.novaTitle, icon: destination.novaIcon) {
                                selectNovaDestination(destination)
                            }
                            .accessibilityAddTraits(novaDestination == destination ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, CodySpacing.lg)
            .padding(.bottom, CodySpacing.sm)
        } history: {
            sessionList(useNavigationLinks: true)
                .padding(.horizontal, 24)
        } actions: {
            novaDrawerActions
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
                    .onSubmit { searchFocused = false }
                if !searchText.isEmpty {
                    novaDrawerIcon("Clear search", icon: "xmark.circle.fill") {
                        searchText = ""
                        scheduleSearch()
                    }
                }
            }
            .padding(.leading, CodySpacing.md)
            .padding(.trailing, searchText.isEmpty ? CodySpacing.md : 0)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())

            Button("Cancel", action: dismissSearch)
                .font(CodyTypography.labelLarge)
                .foregroundStyle(CodyColors.textPrimary)
                .frame(minHeight: 44)
                .buttonStyle(CodyPressableButtonStyle())
        }
    }

    private var novaSelectionHeader: some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            Group {
                if selectedIds.isEmpty {
                    Text("Select Sessions")
                } else {
                    Text("\(selectedIds.count) Selected")
                }
            }
            .font(CodyTypography.titleSmall)
            .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Cancel") {
                    isSelecting = false
                    selectedIds.removeAll()
                }
                Spacer(minLength: CodySpacing.sm)
                let allSelected = !sessions.isEmpty && selectedIds.count == sessions.count
                Button {
                    selectedIds = allSelected ? [] : Set(sessions.map(\.id))
                } label: {
                    if allSelected {
                        Text("Deselect All")
                    } else {
                        Text("Select All")
                    }
                }
            }
            .font(CodyTypography.labelLarge)
            .frame(minHeight: 44)
        }
        .foregroundStyle(CodyColors.textPrimary)
    }

    private func novaDrawerDestination(
        _ title: LocalizedStringKey,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CodySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 17, weight: .medium))
            }
            .foregroundStyle(CodyColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodyPressableButtonStyle())
    }

    var novaSplitDestinations: some View {
        HStack(spacing: CodySpacing.xxs) {
            ForEach(novaPrimaryDestinations) { destination in
                let isSelected = novaDestination == destination
                Button {
                    selectNovaDestination(destination)
                } label: {
                    Image(systemName: destination.novaIcon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(CodyColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSelected ? CodyColors.interactiveSecondaryBg : .clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel(Text(destination.novaTitle))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                novaDrawerDestination("Add a Provider", icon: "plus") { showAddProvider = true }
            } else {
                novaDrawerDestination("Select Models", icon: "cpu") { showSelectModels = true }
            }
            novaDrawerDestination("Restore Backup", icon: "clock.arrow.circlepath") {
                showRestoreBackup = true
            }
        }
        .foregroundStyle(CodyColors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var novaDrawerActions: some View {
        HStack {
            Button(action: startNewNovaChat) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(CodyColors.textAccent, in: Capsule())
                    .shadow(color: CodyColors.textAccent.opacity(0.25), radius: 8, y: 3)
                    .contentShape(Capsule())
            }
            .buttonStyle(CodyPressableButtonStyle())

            Spacer(minLength: CodySpacing.sm)

            HStack(spacing: 0) {
                novaDrawerIcon("Search chats", icon: "magnifyingglass") {
                    if showSearchBar { dismissSearch() }
                    else { focusSearch() }
                }
                .accessibilityAddTraits(showSearchBar ? .isSelected : [])

                Button { openNovaToolSheet(.settings) } label: {
                    SoulIconView(icon: SoulStore.cachedMetadata.icon, size: 20)
                        .frame(width: 30, height: 30)
                        .background(CodyColors.statusSuccessBg, in: Circle())
                        .clipShape(Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel("Settings")
                .accessibilityValue(Text(verbatim: soulName))
                .contextMenu { novaProfileMenu }
            }
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(CodyColors.borderDefault, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var novaProfileMenu: some View {
        if #available(iOS 17.0, *), SyncV2Bootstrap.isEnabled {
            Button { openNovaToolSheet(.syncMigrationDetail) } label: {
                Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
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
    }

    private func openNovaToolSheet(_ sheet: ToolSheet) {
        closeNovaDrawer()
        activeToolSheet = sheet
    }

    private func novaDrawerIcon(_ label: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(CodyColors.iconPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

private extension CodyNovaDestination {
    var novaTitle: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .tool(let tool): tool.title
        case .more: "More"
        }
    }

    var novaIcon: String {
        switch self {
        case .home: "house"
        case .tool(let tool): tool.iconName
        case .more: "square.grid.2x2"
        }
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
