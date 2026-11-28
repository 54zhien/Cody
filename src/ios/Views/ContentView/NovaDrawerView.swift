import SwiftUI

private enum NovaDrawerMetrics {
    static let bottomPillHeight: CGFloat = 56
}

struct NovaDrawerView<PinnedHeader: View, Content: View, Actions: View>: View {
    let showsActions: Bool
    let showsPinnedHeader: Bool
    @ViewBuilder let pinnedHeader: () -> PinnedHeader
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    private var concentricEdgeInset: CGFloat {
        CodyDisplayGeometry.concentricEdgeInset(forCapsuleHeight: NovaDrawerMetrics.bottomPillHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPinnedHeader {
                pinnedHeader()
            }
            contentHost
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if showsActions {
                // Strictly (pillHeight + concentricEdgeInset) tall — zero full-screen Spacer wrapper —
                // aligned concentrically with the physical display corners and fully interactive.
                actions()
                    .padding(.horizontal, concentricEdgeInset)
                    .padding(.bottom, concentricEdgeInset)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
    }

    @ViewBuilder
    private var contentHost: some View {
        let clearance = max(72, NovaDrawerMetrics.bottomPillHeight + concentricEdgeInset - CodyDisplayGeometry.bottomSafeAreaInset + 16)
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive {
            content()
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if showsActions { Color.clear.frame(height: clearance) }
                }
        } else {
            content()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsActions { Color.clear.frame(height: clearance) }
                }
        }
    }
}

extension ContentView {
    var novaPrimaryDestinations: [CodyNovaDestination] {
        [.home] + novaTabStore.pinnedTools.map { .tool($0) } + [.more]
    }

    var novaDrawerHorizontalInset: CGFloat {
        CodyDisplayGeometry.concentricEdgeInset(forCapsuleHeight: NovaDrawerMetrics.bottomPillHeight)
    }

    var novaDrawer: some View {
        let inset = novaDrawerHorizontalInset
        return NovaDrawerView(
            showsActions: !isSelecting,
            showsPinnedHeader: isSelecting || showSearchBar
        ) {
            Group {
                if isSelecting {
                    novaSelectionHeader
                } else if showSearchBar {
                    novaSearchHeader
                }
            }
            .padding(.horizontal, inset)
            .padding(.top, CodySpacing.lg)
            .padding(.bottom, CodySpacing.sm)
        } content: {
            // Whole drawer scrolls as one unified sheet (top nav + Pinned + Chats).
            sessionList(useNavigationLinks: true)
                .padding(.horizontal, inset)
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

    /// Top primary navigation rows rendered inside `stackListBody` so scrolling moves the entire sidebar together.
    @ViewBuilder
    var novaDrawerPrimaryNavRows: some View {
        if !isSelecting && !showSearchBar {
            Section {
                ForEach(novaPrimaryDestinations) { destination in
                    novaDrawerDestination(destination.novaTitle, icon: destination.novaIcon) {
                        selectNovaDestination(destination)
                    }
                    .accessibilityAddTraits(novaDestination == destination ? .isSelected : [])
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .modifier(SelectionDisabledIfAvailable())
                }
            } header: {
                Color.clear
                    .frame(height: 14)
                    .listRowInsets(EdgeInsets())
            }
        }
    }

    private var novaSearchHeader: some View {
        HStack(spacing: CodySpacing.sm) {
            HStack(spacing: CodySpacing.sm) {
                CodyIconView(.search, size: 22)
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
                    novaDrawerIcon("Clear search", icon: .close) {
                        searchText = ""
                        scheduleSearch()
                    }
                }
            }
            .padding(.leading, CodySpacing.md)
            .padding(.trailing, searchText.isEmpty ? CodySpacing.md : 0)
            .frame(minHeight: 48)
            .modifier(NovaDrawerGlassCapsule())

            Button("Cancel", action: dismissSearch)
                .font(CodyTypography.labelLarge)
                .foregroundStyle(CodyColors.textPrimary)
                .frame(minHeight: 48)
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

    func novaDrawerDestination(
        _ title: LocalizedStringKey,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                CodyIconView(systemName: icon, size: 28)
                    .frame(width: 30, height: 30, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 21, weight: .medium))
            }
            .foregroundStyle(CodyColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
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
                    CodyIconView(systemName: destination.novaIcon, size: 24)
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
        let pillHeight = NovaDrawerMetrics.bottomPillHeight
        let avatarSize: CGFloat = 38
        let avatarEdgeInset = (pillHeight - avatarSize) / 2 // 9pt concentric with capsule semicircle

        return HStack {
            Button(action: startNewNovaChat) {
                HStack(spacing: 10) {
                    CodyIconView(.compose, size: 26)
                        .accessibilityHidden(true)
                    Text("New Chat")
                        .font(.system(size: 19, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .frame(height: pillHeight)
                .modifier(NovaDrawerNewChatGlassCapsule())
            }
            .buttonStyle(CodyPressableButtonStyle())

            Spacer(minLength: CodySpacing.sm)

            HStack(spacing: 6) {
                Button {
                    if showSearchBar { dismissSearch() }
                    else { focusSearch() }
                } label: {
                    CodyIconView(.search, size: 27)
                        .foregroundStyle(CodyColors.iconPrimary)
                        .frame(width: 52, height: pillHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel(Text("Search chats"))
                .accessibilityAddTraits(showSearchBar ? .isSelected : [])

                Button { openNovaToolSheet(.settings) } label: {
                    SoulIconView(icon: SoulStore.cachedMetadata.icon, size: 24)
                        .frame(width: avatarSize, height: avatarSize)
                        .background(CodyColors.statusSuccessBg, in: Circle())
                        .clipShape(Circle())
                        .frame(width: avatarSize + 8, height: pillHeight)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, max(0, avatarEdgeInset - 4))
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel("Settings")
                .accessibilityValue(Text(verbatim: soulName))
                .contextMenu { novaProfileMenu }
            }
            .frame(height: pillHeight)
            .modifier(NovaDrawerGlassCapsule())
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

    private func novaDrawerIcon(_ label: LocalizedStringKey, icon: CodyIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CodyIconView(icon, size: 21)
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

private struct NovaDrawerGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(CodyColors.borderDefault, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
    }
}

private struct NovaDrawerNewChatGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let tintBlue = Color(red: 0.22, green: 0.64, blue: 1.0)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            content
                .glassEffect(.regular.tint(Self.tintBlue).interactive(), in: .capsule)
                .contentShape(Capsule())
        } else {
            content
                .background(Self.tintBlue, in: Capsule())
                .shadow(color: Self.tintBlue.opacity(0.28), radius: 10, y: 4)
                .contentShape(Capsule())
        }
    }
}
