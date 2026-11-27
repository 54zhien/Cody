import SwiftUI
import WebKit

struct BrowserManagementView: View {
    @ObservedObject var pool: BrowserTabPool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cookieCount: Int = 0
    @State private var cookies: [HTTPCookie] = []
    @State private var showClearConfirm = false
    @State private var searchText: String = ""
    @State private var customUA: String = ""

    /// Draft viewport inputs. Kept as strings so the user can type freely;
    /// pushed into the pool on commit.
    @State private var viewportWidthText: String = ""
    @State private var viewportHeightText: String = ""
    /// Controls whether the width/height editor row is visible below the
    /// Custom selector. Initialized from the pool on appear.
    @State private var showCustomViewportEditor: Bool = false

    /// Unique domains derived from current cookies.
    private var domains: [DomainGroup] {
        let filtered = searchText.isEmpty
            ? cookies
            : cookies.filter { $0.domain.localizedCaseInsensitiveContains(searchText) }
        let grouped = Dictionary(grouping: filtered) { $0.domain }
        return grouped.map { DomainGroup(domain: $0.key, cookies: $0.value) }
            .sorted { $0.domain < $1.domain }
    }

    var body: some View {
        List {
            userAgentSection
            viewportSection
            cookiesSection
            domainListSection
        }
        .codyGroupedListCanvas()
        .searchable(text: $searchText, prompt: "Filter by domain")
        .navigationTitle("Browser Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Clear All Cookies?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                clearAllCookies()
            }
        } message: {
            Text("This will remove all cookies and website data from the Cody browser.")
        }
        .task {
            await loadCookies()
        }
    }

    // MARK: - User Agent Section

    private var userAgentSection: some View {
        Section {
            userAgentRow(.mobileSafari)
            userAgentRow(.desktopSafari)
            customUserAgentRow
        } header: {
            Text("User Agent")
                .settingsSectionHeading()
        } footer: {
            let vp = pool.userAgentProfile.viewportSize
            Text("Viewport: \(vp.width)×\(vp.height)")
                .settingsSectionFooter()
        }
        // cody-config writes these settings straight to UserDefaults; show
        // what is stored now, not what this pool read when it was created.
        .onAppear { pool.syncGlobalDefaultsFromStore() }
    }

    private func displayUA(for profile: UserAgentProfile) -> String {
        switch profile {
        case .custom:
            return pool.customUserAgentString.isEmpty ? "Not set" : pool.customUserAgentString
        default:
            return profile.userAgentString ?? ""
        }
    }

    private func userAgentRow(_ profile: UserAgentProfile) -> some View {
        let isSelected = pool.userAgentProfile == profile
        return Button {
            pool.setUserAgentProfile(profile)
        } label: {
            HStack(spacing: CodySpacing.md) {
                CodySettingsIconBadge(systemImage: profile.icon, tint: isSelected ? .blue : .neutral)
                VStack(alignment: .leading, spacing: CodySpacing.xs) {
                    Text(profile.displayName)
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                    Text(displayUA(for: profile))
                        .font(CodyTypography.code)
                        .foregroundStyle(CodyColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(CodyColors.textAccent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, CodySpacing.xxs)
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .codyGroupedRow()
        .contextMenu {
            Button {
                UIPasteboard.general.string = displayUA(for: profile)
            } label: {
                Label("Copy User Agent", systemImage: "doc.on.doc")
            }
        }
    }

    private var customUserAgentRow: some View {
        let isSelected = pool.userAgentProfile == .custom
        return VStack(alignment: .leading, spacing: CodySpacing.xsPlus) {
            Button {
                if !customUA.isEmpty {
                    pool.customUserAgentString = customUA
                    pool.setUserAgentProfile(.custom)
                }
            } label: {
                HStack(spacing: CodySpacing.md) {
                    CodySettingsIconBadge(systemImage: "pencil.line", tint: isSelected ? .blue : .neutral)
                    Text("Custom")
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(CodyColors.textAccent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            TextField("Enter custom user agent...", text: $customUA, axis: .vertical)
                .font(CodyTypography.code)
                .foregroundStyle(CodyColors.textSecondary)
                .lineLimit(2...4)
                .onSubmit {
                    pool.customUserAgentString = customUA
                    pool.setUserAgentProfile(.custom)
                }
        }
        .padding(.vertical, CodySpacing.xxs)
        .codyGroupedRow()
        .onAppear {
            customUA = pool.customUserAgentString
        }
        .contextMenu {
            if !customUA.isEmpty {
                Button {
                    UIPasteboard.general.string = customUA
                } label: {
                    Label("Copy User Agent", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Viewport Section

    private var viewportSection: some View {
        Section {
            defaultViewportRow
            customViewportRow
            if showCustomViewportEditor {
                customViewportEditor
            }
        } header: {
            Text("Web Viewport")
                .settingsSectionHeading()
        } footer: {
            let vp = pool.resolvedViewportSize()
            Group {
                if pool.customViewportWidth > 0 && pool.customViewportHeight > 0 {
                    Text("Using custom viewport \(vp.width)×\(vp.height). Tap Default to revert to the UA default.")
                } else {
                    Text("Using UA default \(vp.width)×\(vp.height). Set a custom size to override.")
                }
            }
            .settingsSectionFooter()
        }
        .onAppear {
            pool.syncGlobalDefaultsFromStore()
            if pool.customViewportWidth > 0 {
                viewportWidthText = String(pool.customViewportWidth)
            }
            if pool.customViewportHeight > 0 {
                viewportHeightText = String(pool.customViewportHeight)
            }
            showCustomViewportEditor = isCustomViewportActive
        }
    }

    private var isCustomViewportActive: Bool {
        pool.customViewportWidth > 0 && pool.customViewportHeight > 0
    }

    private var defaultViewportRow: some View {
        Button {
            pool.setGlobalViewport(width: 0, height: 0)
            viewportWidthText = ""
            viewportHeightText = ""
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                showCustomViewportEditor = false
            }
        } label: {
            HStack(spacing: CodySpacing.md) {
                CodySettingsIconBadge(systemImage: "arrow.counterclockwise", tint: !isCustomViewportActive ? .blue : .neutral)
                Text("Default (auto by UA)")
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                Spacer()
                if !isCustomViewportActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(CodyColors.textAccent)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityAddTraits(!isCustomViewportActive ? .isSelected : [])
        .codyGroupedRow()
    }

    private var customViewportRow: some View {
        Button {
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                showCustomViewportEditor = true
            }
            commitCustomViewport()
        } label: {
            HStack(spacing: CodySpacing.md) {
                CodySettingsIconBadge(systemImage: "aspectratio", tint: isCustomViewportActive ? .blue : .neutral)
                Text("Custom")
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                Spacer()
                if isCustomViewportActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(CodyColors.textAccent)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityAddTraits(isCustomViewportActive ? .isSelected : [])
        .codyGroupedRow()
    }

    /// Common viewport presets shown under the editor. Mix of mobile and
    /// desktop sizes that roughly match what agents and users pick in
    /// practice.
    private static let viewportPresets: [(label: String, width: Int, height: Int)] = [
        ("iPhone",      390,  844),
        ("iPhone Pro",  430,  932),
        ("iPad",        820, 1180),
        ("Laptop",     1280,  800),
        ("Desktop",    1440,  900),
        ("Full HD",    1920, 1080),
    ]

    /// Expanded editor row shown only while the user is configuring a custom
    /// viewport. Visually distinct from the selector row above so the sizes
    /// read as a single value rather than a separate choice.
    private var customViewportEditor: some View {
        VStack(alignment: .center, spacing: CodySpacing.smPlus) {
            HStack(spacing: CodySpacing.smPlus) {
                Spacer()
                viewportField(placeholder: "Width", text: $viewportWidthText)
                Text("×")
                    .foregroundStyle(CodyColors.textSecondary)
                viewportField(placeholder: "Height", text: $viewportHeightText)
                Spacer()
            }
            if let warning = viewportUAMismatchWarning {
                uaMismatchBanner(warning)
            }
            quickSetPresets
        }
        .padding(.vertical, CodySpacing.xs)
        .codyGroupedRow()
    }

    private func viewportField(placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
        return TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .font(CodyTypography.code)
            .monospacedDigit()
            .foregroundStyle(CodyColors.textPrimary)
            .multilineTextAlignment(.center)
            .frame(width: 76, height: CodyControlHeight.sm)
            .background(shape.fill(CodyColors.bgSecondary))
            .overlay {
                shape.strokeBorder(CodyColors.borderInput, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .onSubmit { commitCustomViewport() }
    }

    /// Returns a warning message when the active viewport width crosses the
    /// mobile/desktop breakpoint for the current UA profile — sites using
    /// UA-sniffing (not just CSS media queries) will hand back layouts the
    /// other form factor can't render cleanly.
    private var viewportUAMismatchWarning: String? {
        // Prefer the staged text so the banner updates as the user types;
        // fall back to the committed pool value when fields are empty.
        let width: Int
        if let w = Int(viewportWidthText.trimmingCharacters(in: .whitespaces)), w > 0 {
            width = w
        } else if pool.customViewportWidth > 0 {
            width = pool.customViewportWidth
        } else {
            return nil
        }
        let breakpoint = 768
        switch pool.userAgentProfile {
        case .mobileSafari, .custom:
            if width >= breakpoint {
                return "Viewport ≥\(breakpoint)px while UA is Mobile — sites may serve a desktop layout that renders awkwardly. Consider switching UA to Desktop."
            }
        case .desktopSafari:
            if width < breakpoint {
                return "Viewport <\(breakpoint)px while UA is Desktop — sites may serve a mobile layout that renders awkwardly. Consider switching UA to Mobile."
            }
        }
        return nil
    }

    private func uaMismatchBanner(_ message: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
        return HStack(alignment: .top, spacing: CodySpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CodyColors.statusWarningText)
                .accessibilityHidden(true)
            Text(message)
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CodySpacing.md)
        .padding(.vertical, CodySpacing.sm)
        .background(shape.fill(CodyColors.statusWarningBg))
        .overlay {
            shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                .allowsHitTesting(false)
        }
    }

    private var quickSetPresets: some View {
        VStack(alignment: .leading, spacing: CodySpacing.xsPlus) {
            Text("Quick Set")
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CodySpacing.sm) {
                    ForEach(Self.viewportPresets, id: \.label) { preset in
                        let active = isPresetActive(preset)
                        Button {
                            viewportWidthText = String(preset.width)
                            viewportHeightText = String(preset.height)
                            pool.setGlobalViewport(width: preset.width, height: preset.height)
                        } label: {
                            VStack(spacing: CodySpacing.xxs) {
                                Text(preset.label)
                                    .font(CodyTypography.labelMedium)
                                Text("\(preset.width)×\(preset.height)")
                                    .font(CodyTypography.labelSmall)
                                    .monospacedDigit()
                                    .foregroundStyle(active ? CodyColors.textAccent : CodyColors.textSecondary)
                            }
                            .padding(.horizontal, CodySpacing.smPlus)
                            .padding(.vertical, CodySpacing.xsPlus)
                            .background(
                                active ? CodyColors.bgProgressTrack : CodyColors.bgSecondary,
                                in: RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
                            )
                            .foregroundStyle(active ? CodyColors.textAccent : CodyColors.textPrimary)
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func isPresetActive(_ preset: (label: String, width: Int, height: Int)) -> Bool {
        pool.customViewportWidth == preset.width && pool.customViewportHeight == preset.height
    }

    private func commitCustomViewport() {
        guard let w = Int(viewportWidthText.trimmingCharacters(in: .whitespaces)),
              let h = Int(viewportHeightText.trimmingCharacters(in: .whitespaces)),
              w > 0, h > 0 else {
            return
        }
        pool.setGlobalViewport(width: w, height: h)
    }

    // MARK: - Cookies Section

    private var cookiesSection: some View {
        Section {
            HStack {
                Text("Cookies")
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                Spacer()
                Text("\(cookieCount)")
                    .font(CodyTypography.bodyMedium)
                    .monospacedDigit()
                    .foregroundStyle(CodyColors.textSecondary)
            }
            .codyGroupedRow()

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear All Cookies", systemImage: "trash")
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.statusErrorText)
            }
            .buttonStyle(CodyPressableButtonStyle())
            .disabled(cookieCount == 0)
            .codyGroupedRow()
        } header: {
            Text("Cookies & Data")
                .settingsSectionHeading()
        } footer: {
            Text("Clearing cookies will sign you out of all websites in the Cody browser.")
                .settingsSectionFooter()
        }
    }

    // MARK: - Domain List Section

    @ViewBuilder
    private var domainListSection: some View {
        if !domains.isEmpty {
            Section {
                ForEach(domains) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                            Text(group.domain)
                                .font(CodyTypography.bodyMedium)
                                .foregroundStyle(CodyColors.textPrimary)
                            Text("\(group.cookies.count) cookie\(group.cookies.count == 1 ? "" : "s")")
                                .font(CodyTypography.bodySmall)
                                .monospacedDigit()
                                .foregroundStyle(CodyColors.textSecondary)
                        }
                        Spacer()
                    }
                    .codyGroupedRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            clearCookies(for: group.domain)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Group {
                    if searchText.isEmpty {
                        Text("Domains")
                    } else {
                        Text("Results")
                    }
                }
                .settingsSectionHeading()
            }
        }
    }

    // MARK: - Data

    /// All browser WKWebViews share `.default()` data store, so query it directly
    /// instead of going through activeManager (which may be nil).
    private var cookieStore: WKHTTPCookieStore {
        WKWebsiteDataStore.default().httpCookieStore
    }

    private func loadCookies() async {
        let all = await cookieStore.allCookies()
        cookies = all.sorted { $0.domain < $1.domain }
        cookieCount = all.count
    }

    private func clearAllCookies() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
            cookies = []
            cookieCount = 0
            // Also wipe the anti-ITP backup so nothing is restored on next sync.
            Task { await CookieBackupStore.shared.forgetAll() }
        }
    }

    private func clearCookies(for domain: String) {
        let store = cookieStore
        let toDelete = cookies.filter { $0.domain == domain }
        Task {
            for cookie in toDelete {
                await store.deleteCookie(cookie)
            }
            // Update local state directly instead of re-fetching from store,
            // which may return stale data before deletions are fully persisted.
            cookies.removeAll { $0.domain == domain }
            cookieCount = cookies.count
            // Reconcile the backup so the deleted cookies aren't resurrected
            // on the next sync (keeps any sibling-subdomain cookies still live).
            await CookieBackupStore.shared.reconcileDomainAfterUserEdit(domain)
        }
    }
}

// MARK: - Domain Group

private struct DomainGroup: Identifiable {
    let domain: String
    let cookies: [HTTPCookie]
    var id: String { domain }
}
