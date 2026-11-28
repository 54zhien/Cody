//
//  SettingsSheet.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  The settings screen presented from the home toolbar: its navigation
//  destinations and the top-level cards linking to every settings page.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Settings Sheet

private enum SettingsDestination: Hashable {
    case providers
    case providerDetail(instanceId: String)
    case modelGroups
    case modelGroupDetail(groupId: String)
    case usage
    case skills
    // [T-ios-assistant-header-open-soul]
    case soul
    // [T-tools-master-switch]
    case tools
    case memory
    case storage
    case mountedFolders
    case sharedFolders
    case logs
    case appearance
    case background
    case about
    case permissions
    case environments
    // [T-mcp-oauth-deeplink]
    case mcpIntegrations
    case mcpServerDetail(serverId: String)
}

struct SettingsSheet: View {
    @Binding var showTerminal: Bool
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var deepLink = DeepLinkCoordinator.shared
    @ObservedObject private var providers = ProviderConfigStore.shared
    @State private var soul = SoulStore.cachedMetadata
    @State private var navPath = NavigationPath()
    @State private var showFeedbackDialog = false

    var body: some View {
        NavigationStack(path: $navPath) {
            CodySettingsScrollPage {
                accountSection
                customizeSection
                capabilitiesSection
                dataSection
                diagnosticsSection
                feedbackSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(CodyColors.bgCanvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        toolbarIcon("xmark")
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityLabel(Text("Close"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navPath.append(SettingsDestination.about) } label: {
                        toolbarIcon("info.circle")
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityLabel(Text("About Cody"))
                }
            }
            .navigationDestination(for: SettingsDestination.self) { dest in
                switch dest {
                case .providers:
                    ProviderInstancesView()
                case .providerDetail(let id):
                    ProviderInstanceDetailView(instanceId: id)
                case .modelGroups:
                    ModelGroupsView()
                case .modelGroupDetail(let id):
                    ModelGroupDetailView(groupId: id)
                case .usage:
                    UsageStatsView()
                case .skills:
                    SkillsManagementView()
                case .soul:
                    SoulSettingsView()
                case .tools:
                    ToolsSettingsView()
                case .memory:
                    MemoryManagementView()
                case .storage:
                    StorageManagementView()
                case .mountedFolders:
                    MountedFoldersSettingsView()
                case .sharedFolders:
                    SharedFoldersSettingsView()
                case .logs:
                    // Pull a one-shot tab hint from the deep link router
                    // (e.g. `?tab=config-audit`). LogManagementView clears
                    // its local state independently; the published value
                    // here is consumed once and reset to nil.
                    LogManagementView(initialTab: deepLink.pendingLogsTab ?? "logs")
                        .onAppear { deepLink.pendingLogsTab = nil }
                case .appearance:
                    AppearanceSettingsView()
                case .background:
                    EnhancedBackgroundSettingsView()
                case .about:
                    AboutView()
                case .environments:
                    EnvironmentVariablesView()
                case .permissions:
                    OffloadPermissionSettingsView()
                // [T-mcp-oauth-deeplink] Detail = the list view told to open
                // the server's edit sheet on appear; a deleted/unknown server
                // just lands on the list (no crash, sensible fallback).
                case .mcpIntegrations:
                    MCPIntegrationsView()
                case .mcpServerDetail(let serverId):
                    MCPIntegrationsView(initialEditServerId: serverId)
                }
            }
            .onAppear {
                applyPendingDeepLink()
                // Legacy flags — kept so older call sites keep working.
                if deepLink.showEnvironmentVariables {
                    navPath.append(SettingsDestination.environments)
                    deepLink.showEnvironmentVariables = false
                }
                if deepLink.showPermissions {
                    navPath.append(SettingsDestination.permissions)
                    deepLink.showPermissions = false
                }
                // Restore the user's location after a language-change rebuild.
                // AppearanceSettingsView's language picker writes this flag
                // right before flipping `appLanguage`, knowing the root
                // `.id(appLanguage)` will tear the whole tree down. ContentView
                // re-opens the sheet on re-mount; here we push back to the
                // destination so the user lands where they were, now rendered
                // in the new language.
                if let dest = UserDefaults.standard.string(forKey: "pendingSettingsReopen") {
                    UserDefaults.standard.removeObject(forKey: "pendingSettingsReopen")
                    switch dest {
                    case "appearance":
                        navPath.append(SettingsDestination.appearance)
                    default:
                        break
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
                soul = SoulStore.cachedMetadata
            }
            .onChange(of: deepLink.pendingSettingsTarget) { _ in
                applyPendingDeepLink()
            }
        }
        .preferredColorScheme(appearanceMode == 1 ? .light : appearanceMode == 2 ? .dark : nil)
        .appFontScale()
    }

    private func toolbarIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(CodyColors.iconPrimary)
            .frame(width: 44, height: 44)
            .background(CodySettingsHairline.cardFill, in: Circle())
            .overlay { Circle().strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px) }
            .contentShape(Circle())
            .accessibilityHidden(true)
    }

    private var accountSection: some View {
        CodySettingsNovaSection {
            NavigationLink {
                SoulSettingsView()
            } label: {
                HStack(spacing: 10) {
                    SoulIconView(icon: soul.icon, size: SoulIconImage.isDataURI(soul.icon) ? 28 : 18)
                        .frame(width: 28, height: 28)
                        .background(CodySettingsHairline.cardFill, in: Circle())
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px) }
                        .accessibilityHidden(true)
                    Text("Soul")
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                    Spacer(minLength: CodySpacing.sm)
                    value(Text(verbatim: soul.name.isEmpty ? "Cody" : soul.name))
                        .lineLimit(1)
                    SettingsNovaDisclosure()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(CodyPressableButtonStyle())
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Manage Providers", systemImage: "plus") {
                value(Text(providers.instances.count, format: .number))
                    .accessibilityLabel(Text("\(providers.instances.count) providers"))
            } destination: {
                ProviderInstancesView()
            }
        }
    }

    private var customizeSection: some View {
        CodySettingsNovaSection {
            CodySettingsNovaNavRow("Customize Cody", subtitle: "Soul, Memory, Skills & MCP", systemImage: "slider.horizontal.3") {
                SoulSettingsView()
            }
        }
    }

    private var capabilitiesSection: some View {
        CodySettingsNovaSection {
            CodySettingsNovaNavRow("Appearance", systemImage: "gearshape") {
                value(Text(appearanceLabel))
            } destination: {
                AppearanceSettingsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Model Groups", systemImage: "square.3.layers.3d") {
                ModelGroupsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Token Usage", systemImage: "chart.line.uptrend.xyaxis") {
                UsageStatsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Agent Tools", systemImage: "wrench.and.screwdriver") {
                ToolsSettingsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Sub Agents", systemImage: "sparkles") {
                HelperSettingsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Skills", systemImage: "puzzlepiece.extension") {
                SkillsManagementView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Memory", systemImage: "brain.head.profile") {
                MemoryManagementView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("MCP Integrations", systemImage: "square.stack.3d.up") {
                MCPIntegrationsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Environment Variables", systemImage: "terminal") {
                EnvironmentVariablesView()
            }
        }
    }

    private var dataSection: some View {
        CodySettingsNovaSection {
            if #available(iOS 17.0, *) {
                CodySettingsNovaNavRow("iCloud Sync", systemImage: "icloud") {
                    CloudSyncSettingsV2View()
                }
                CodySettingsNovaDivider(leadingInset: 54)
            }
            CodySettingsNovaNavRow("Backup & Restore", systemImage: "arrow.triangle.2.circlepath") {
                BackupAndRestoreView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Storage", systemImage: "externaldrive") {
                StorageManagementView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Shared Folders", systemImage: "folder") {
                SharedFoldersSettingsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Mount External Folders", systemImage: "externaldrive.badge.plus") {
                MountedFoldersSettingsView()
            }
        }
    }

    private var diagnosticsSection: some View {
        CodySettingsNovaSection {
            CodySettingsNovaNavRow("Background & Awake", systemImage: "moon") {
                EnhancedBackgroundSettingsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Permissions", systemImage: "checkmark.shield") {
                OffloadPermissionSettingsView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaNavRow("Diagnostic Logs", systemImage: "doc.text") {
                LogManagementView()
            }
            CodySettingsNovaDivider(leadingInset: 54)
            CodySettingsNovaActionRow(
                "Linux Terminal",
                systemImage: UIImage(systemName: "apple.terminal") == nil ? "terminal" : "apple.terminal"
            ) {
                showTerminal = true
                dismiss()
            }
        }
    }

    private var feedbackSection: some View {
        CodySettingsNovaSection {
            CodySettingsNovaActionRow("Feedback", systemImage: "bubble.left.and.bubble.right") {
                showFeedbackDialog = true
            }
            .confirmationDialog("Feedback", isPresented: $showFeedbackDialog, titleVisibility: .visible) {
                Button("Report a Bug (GitHub)") {
                    if let url = Self.makeBugReportURL() { UIApplication.shared.open(url) }
                }
                Button("Feedback (Telegram)") {
                    if let url = URL(string: "https://t.me/+2NzhOJuzRyI1YmM1") { UIApplication.shared.open(url) }
                }
                Button("Feedback (Email)") {
                    if let url = Self.makeFeedbackEmailURL() { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var appearanceLabel: LocalizedStringKey {
        switch appearanceMode {
        case 1: "Light"
        case 2: "Dark"
        default: "System"
        }
    }

    private func value(_ text: Text) -> some View {
        text
            .font(CodyTypography.bodySmall)
            .foregroundStyle(CodyColors.textSecondary)
            .multilineTextAlignment(.trailing)
    }

    /// Translate `DeepLinkCoordinator.pendingSettingsTarget` into a
    /// NavigationStack push and clear the pending value. Called from
    /// `onAppear` (cold-start deep link) and `onChange` (deep link
    /// arriving while the sheet is already open).
    ///
    /// `.environments` keeps its existing prefill semantics — the
    /// environments view consumes `pendingEnvVarCreate` separately on
    /// appear, so we only have to navigate here.
    private func applyPendingDeepLink() {
        guard let target = deepLink.pendingSettingsTarget else { return }
        // Reset path so deep links are predictable: a deep link always
        // lands on the requested destination as the only stack entry,
        // not on top of whatever the user was browsing earlier.
        navPath = NavigationPath()
        switch target {
        case .home:
            break // already at Settings root
        case .providers:
            navPath.append(SettingsDestination.providers)
        case .providerDetail(let id):
            navPath.append(SettingsDestination.providers)
            navPath.append(SettingsDestination.providerDetail(instanceId: id))
        case .modelGroups:
            navPath.append(SettingsDestination.modelGroups)
        case .modelGroupDetail(let id):
            navPath.append(SettingsDestination.modelGroups)
            navPath.append(SettingsDestination.modelGroupDetail(groupId: id))
        case .usage:
            navPath.append(SettingsDestination.usage)
        case .skills:
            navPath.append(SettingsDestination.skills)
        case .soul:
            navPath.append(SettingsDestination.soul)
        case .tools:
            navPath.append(SettingsDestination.tools)
        case .memory:
            navPath.append(SettingsDestination.memory)
        case .storage:
            navPath.append(SettingsDestination.storage)
        case .mountedFolders:
            navPath.append(SettingsDestination.mountedFolders)
        case .sharedFolders:
            navPath.append(SettingsDestination.sharedFolders)
        case .logs:
            navPath.append(SettingsDestination.logs)
        case .appearance:
            navPath.append(SettingsDestination.appearance)
        case .background:
            navPath.append(SettingsDestination.background)
        case .about:
            navPath.append(SettingsDestination.about)
        case .permissions:
            navPath.append(SettingsDestination.permissions)
        case .environments:
            navPath.append(SettingsDestination.environments)
        case .mcpIntegrations:
            navPath.append(SettingsDestination.mcpIntegrations)
        case .mcpServerDetail(let id):
            navPath.append(SettingsDestination.mcpServerDetail(serverId: id))
        }
        deepLink.pendingSettingsTarget = nil
    }

    /// Compose the feedback mailto URL with a prefilled body that includes
    /// app version, iOS version, and a machine identifier, plus a prompt
    /// asking the user to attach a screenshot manually (mailto:// can't
    /// auto-attach). Using URLComponents so the subject and body go through
    /// proper URL encoding without hand-rolling addingPercentEncoding calls.
    fileprivate static func makeFeedbackEmailURL() -> URL? {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let iosVersion = UIDevice.current.systemVersion
        let device = machineIdentifier()

        let body = """
        Please describe your feedback:


        ---
        App Version: \(appVersion) (\(build))
        iOS Version: \(iosVersion)
        Device: \(device)

        Screenshot (optional): Please attach a screenshot if relevant.
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "54zhien@users.noreply.github.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Cody Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// Build the GitHub Issue URL with a bilingual bug-report template
    /// pre-filled with platform / OS / app / device info. SwiftUI `Link`
    /// hands the URL to UIApplication.shared.open, which routes to Safari.
    fileprivate static func makeBugReportURL() -> URL? {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let iosVersion = UIDevice.current.systemVersion
        let device = machineIdentifier()

        let body = """
        ## 📝 Problem Summary

        <!-- Briefly describe the issue you encountered -->


        ## 📱 Basic Information

        | Field | Value |
        |-------|-------|
        | Platform | iOS |
        | OS Version | iOS \(iosVersion) |
        | Cody Version | \(appVersion) (build \(build)) |
        | Device Model | \(device) |

        ## 🔁 Steps to Reproduce

        1.
        2.
        3.

        ## ❌ Error Details

        ```
        paste error here
        ```

        ## ✅ Expected Behavior



        ## 🗂️ Additional Information

        """

        var components = URLComponents(string: "https://github.com/54zhien/Cody/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.md"),
            URLQueryItem(name: "title", value: "[Bug] "),
            URLQueryItem(name: "body", value: body),
        ]
        return components?.url
    }

    /// Returns the hardware model identifier, e.g. "iPhone16,2".
    /// `UIDevice.current.model` returns the generic "iPhone" / "iPad" and
    /// isn't useful in a bug report, so we fall back to utsname.
    private static func machineIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        let id = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}

extension View {
    /// Inset a native control or custom label inside a Nova section.
    func settingsNovaControlRow(minHeight: CGFloat = CodyMetrics.Settings.rowMinHeight) -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, CodySpacing.sm)
            .font(CodyTypography.bodyLarge)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
    }

    func settingsNovaField(_ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(CodyColors.textSecondary)
                .padding(.leading, 18)
                .accessibilityHidden(true)
            self
                .accessibilityLabel(Text(title))
                .foregroundStyle(CodyColors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, CodySpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .codySettingsCapsulePill()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Card surface for rows that still need SwiftUI's native List gestures.
    func settingsNovaListCardRow(minHeight: CGFloat = CodyMetrics.Settings.rowMinHeight) -> some View {
        CodySettingsNovaSection {
            settingsNovaControlRow(minHeight: minHeight)
        }
        .listRowInsets(EdgeInsets(top: CodySpacing.xs, leading: CodySpacing.lg,
                                 bottom: CodySpacing.xs, trailing: CodySpacing.lg))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    func settingsNovaFooter() -> some View {
        self
            .font(CodyTypography.bodySmall)
            .foregroundStyle(CodyColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
    }

    func settingsGroupedCanvas() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgCanvas.ignoresSafeArea())
    }

    func settingsSectionHeading() -> some View {
        self
            .font(CodyTypography.sectionHeader)
            .foregroundStyle(CodyColors.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    func settingsSectionFooter() -> some View {
        self
            .font(CodyTypography.bodySmall)
            .foregroundStyle(CodyColors.textTertiary)
    }

    func settingsRowActionLabel() -> some View {
        frame(maxWidth: .infinity, minHeight: CodyControlHeight.standard, alignment: .leading)
            .contentShape(Rectangle())
    }

    func settingsRowSurface() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(CodySettingsHairline.cardFill)
    }
}

struct SettingsNovaEditorActions: View {
    var title: LocalizedStringKey = "Save"
    var isSaveDisabled = false
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: CodySpacing.xs) {
            Button(action: save) {
                Text(title)
                    .font(CodyTypography.titleSmall)
                    .frame(minWidth: 120, minHeight: 24)
            }
            .buttonStyle(CodyPrimaryCapsuleButtonStyle())
            .disabled(isSaveDisabled)

            Button(role: .cancel, action: cancel) {
                Text("Cancel")
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textSecondary)
                    .frame(minWidth: 88, minHeight: 44)
            }
            .buttonStyle(CodyPressableButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsNovaDisclosure: View {
    var systemImage = "chevron.forward"

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CodyColors.iconDisclosure.opacity(0.75))
            .accessibilityHidden(true)
    }
}

struct SettingsNovaPickerLabel: View {
    let title: LocalizedStringKey
    let value: Text

    var body: some View {
        CodySettingsNovaRowContent(title: title, subtitle: nil, systemImage: nil, tint: nil, showsDisclosure: false) {
            value
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
                .multilineTextAlignment(.trailing)
            SettingsNovaDisclosure(systemImage: "chevron.up.chevron.down")
        }
    }
}

struct SettingsNovaRowMenu<Actions: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Menu(content: actions) {
            Image(systemName: "ellipsis")
                .font(CodyTypography.titleMedium)
                .foregroundStyle(CodyColors.iconSecondary)
                .frame(width: CodyControlHeight.standard, height: CodyControlHeight.standard)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(title))
    }
}

struct SettingsIconLabel: View {
    let title: Text
    let systemImage: String
    var tint: CodyCategoryTint? = nil

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(tint == .red ? CodyColors.statusErrorText : CodyColors.iconPrimary)
        }
    }
}

#Preview {
    ContentView()
}
