import SwiftUI

/// Sheet view for observing the browser's live WKWebView(s) via a tab pool.
struct BrowserSheetView: View {
    @ObservedObject var pool: BrowserTabPool
    var isAgentBusy: Bool = false
    var onTakeover: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var addressText: String = ""
    @State private var showHistory = false
    @State private var isFullscreen = false
    @FocusState private var addressFocused: Bool

    private var manager: BrowserUseManager? { pool.activeManager }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isFullscreen {
                    // Tab bar
                    tabBar
                        .allowsHitTesting(!isAgentBusy)

                    // URL bar
                    HStack(spacing: CodySpacing.sm) {
                        BrowserAddressBarIcon(isLoading: manager?.isLoading ?? false)

                        TextField("Search or enter URL", text: $addressText)
                            .font(CodyTypography.code)
                            .foregroundStyle(CodyColors.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .focused($addressFocused)
                            .disabled(isAgentBusy)
                            .onSubmit {
                                let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                pool.touchActivity()
                                manager?.loadURL(trimmed)
                            }

                        if manager?.isLoading ?? false {
                            Button { manager?.webView.stopLoading() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(CodyColors.iconSecondary)
                            }
                            .buttonStyle(CodyPressableButtonStyle())
                            .accessibilityLabel(Text("Stop"))
                            .transition(.identity)
                        }
                    }
                    .padding(.horizontal, CodySpacing.md)
                    .padding(.vertical, CodySpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                            .fill(CodyColors.bgGroupedSurface)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
                            .strokeBorder(CodyColors.borderInput, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, CodySpacing.md)
                    .padding(.vertical, CodySpacing.sm)
                    .background(CodyColors.bgGrouped)
                    .allowsHitTesting(!isAgentBusy)
                }

                // Live webview + agent overlay
                ZStack {
                    if let manager {
                        BrowserWebView(manager: manager)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .id(pool.selectedTabId)
                        // [T-ios-webview-error-ui] Safari-style error overlay for
                        // agent/manual navigation failures (blank page otherwise).
                        BrowserLoadErrorOverlay(manager: manager)
                    } else {
                        CodyColors.bgCanvas
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if isAgentBusy {
                        AgentBrowsingOverlay(onTakeover: onTakeover)
                            .transition(reduceMotion ? .identity : .opacity)
                    }

                    // Fullscreen exit button
                    if isFullscreen {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(CodyMotion.resolved(CodyMotion.layout, reduceMotion: reduceMotion)) {
                                        isFullscreen = false
                                    }
                                } label: {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(CodyColors.interactivePrimaryLabel)
                                        .padding(CodySpacing.sm)
                                        .background(
                                            Circle().fill(
                                                reduceTransparency
                                                    ? CodyColors.interactivePrimaryBg
                                                    : CodyColors.interactivePrimaryBg.opacity(0.85)
                                            )
                                        )
                                }
                                .buttonStyle(CodyPressableButtonStyle())
                                .accessibilityLabel(Text("Exit Fullscreen"))
                                .padding(.trailing, CodySpacing.md)
                                .padding(.top, CodySpacing.sm)
                            }
                            Spacer()
                        }
                    }
                }
                .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isAgentBusy)

                // Download progress banner — visible in both normal and
                // fullscreen modes so an in-flight download is never silent.
                if let manager {
                    BrowserDownloadBanner(manager: manager)
                }

                if !isFullscreen {
                    // Separator
                    Divider()
                        .overlay(CodyColors.separator)

                    // Bottom navigation toolbar
                    HStack(spacing: 0) {
                        Button { pool.touchActivity(); manager?.goBack() } label: {
                            Image(systemName: "chevron.left")
                                .frame(maxWidth: .infinity, minHeight: CodyControlHeight.sm)
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .disabled(isAgentBusy || !(manager?.canGoBack ?? false))
                        .accessibilityLabel(Text("Back"))

                        Button { pool.touchActivity(); manager?.goForward() } label: {
                            Image(systemName: "chevron.right")
                                .frame(maxWidth: .infinity, minHeight: CodyControlHeight.sm)
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .disabled(isAgentBusy || !(manager?.canGoForward ?? false))
                        .accessibilityLabel(Text("Forward"))

                        if manager?.isLoading ?? false {
                            Button { pool.touchActivity(); manager?.stopLoading() } label: {
                                Image(systemName: "xmark")
                                    .frame(maxWidth: .infinity, minHeight: CodyControlHeight.sm)
                            }
                            .buttonStyle(CodyPressableButtonStyle())
                            .disabled(isAgentBusy)
                            .accessibilityLabel(Text("Stop"))
                            .transition(.identity)
                        } else {
                            Button { pool.touchActivity(); manager?.reload() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, minHeight: CodyControlHeight.sm)
                            }
                            .buttonStyle(CodyPressableButtonStyle())
                            .transition(.identity)
                            .disabled(isAgentBusy)
                            .accessibilityLabel(Text("Reload"))
                        }

                        Button {
                            withAnimation(CodyMotion.resolved(CodyMotion.layout, reduceMotion: reduceMotion)) {
                                isFullscreen = true
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity, minHeight: CodyControlHeight.sm)
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .disabled(isAgentBusy)
                        .accessibilityLabel(Text("Fullscreen"))
                    }
                    .font(.system(size: 18))
                    .foregroundStyle(CodyColors.iconPrimary)
                    .padding(.vertical, CodySpacing.sm)
                    .background(CodyColors.bgGrouped)
                    .allowsHitTesting(!isAgentBusy)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: CodySpacing.xsPlus) {
                        // The selected tab's own profile - what the page on
                        // screen was loaded with - not the global default,
                        // which only says what the NEXT tab will get.
                        Image(systemName: UserAgentProfile.panelProfile(
                            activeTab: pool.activeManager?.currentProfile,
                            globalDefault: pool.userAgentProfile).icon)
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(CodyColors.iconSecondary)
                            .accessibilityHidden(true)
                        Text(navigationTitle)
                            .font(CodyTypography.titleMedium)
                            .foregroundStyle(CodyColors.textPrimary)
                            .lineLimit(1)
                    }
                }
            }
            .toolbar(isFullscreen ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: CodySpacing.md) {
                        Button {
                            _ = pool.newTab()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isAgentBusy || pool.tabs.count >= BrowserTabPool.maxTabs)
                        .accessibilityLabel(Text("New Tab"))

                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .disabled(isAgentBusy)
                        .accessibilityLabel(Text("History"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { addressFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel(Text("Dismiss keyboard"))
                }
            }
            .sheet(isPresented: $showHistory) {
                BrowserHistoryView(historyStore: BrowserHistoryStore.shared) { url in
                    // Ensure a tab exists, then navigate
                    if pool.tabs.isEmpty {
                        pool.ensureTabForUI()
                    }
                    manager?.loadURL(url)
                }
            }
            .onAppear {
                // Ensure at least one tab exists when opened manually
                if pool.tabs.isEmpty {
                    pool.ensureTabForUI()
                }
                addressText = manager?.currentURL ?? ""
            }
            .onDisappear {
                // The sheet stretched each tab's offscreen WKWebView to the
                // sheet width (~620pt), reflowing the page's CSS viewport away
                // from the configured size. Restore every tab's frame + force
                // a reflow so subsequent agent screenshots capture the page at
                // its intended viewport (e.g. 390) instead of a 620-wide
                // layout squeezed into a 390 rect.
                // (T-ios-browser-sheet-viewport-pollution)
                for tab in pool.tabs {
                    tab.manager.restoreViewportFrame()
                }
            }
            .onChange(of: manager?.currentURL) { newURL in
                if !addressFocused {
                    addressText = newURL ?? ""
                }
            }
            .onChange(of: pool.selectedTabId) { _ in
                addressText = manager?.currentURL ?? ""
            }
        }
    }

    private var navigationTitle: String {
        let title = manager?.pageTitle ?? ""
        return title.isEmpty ? "Browser" : title
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CodySpacing.xsPlus) {
                ForEach(pool.tabs) { tab in
                    tabButton(for: tab)
                }

                // Tab count badge
                Text("\(pool.tabs.count)/\(BrowserTabPool.maxTabs)")
                    .font(CodyTypography.labelSmall)
                    .monospacedDigit()
                    .foregroundStyle(CodyColors.textTertiary)
                    .padding(.leading, CodySpacing.xs)
            }
            .padding(.horizontal, CodySpacing.md)
            .padding(.vertical, CodySpacing.xsPlus)
        }
        .background(CodyColors.bgGrouped)
        .overlay(alignment: .bottom) {
            Divider().overlay(CodyColors.separator)
        }
    }

    private func tabButton(for tab: BrowserTabPool.Tab) -> some View {
        let isSelected = tab.id == pool.selectedTabId
        return Button {
            pool.selectedTabId = tab.id
        } label: {
            HStack(spacing: CodySpacing.xs) {
                Text(tabLabel(for: tab))
                    .font(isSelected ? CodyTypography.labelMedium : CodyTypography.bodySmall)
                    .foregroundStyle(isSelected ? CodyColors.textAccent : CodyColors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)

                if !isAgentBusy {
                    Button {
                        _ = pool.closeTab(id: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CodyColors.iconSecondary)
                    }
                    .buttonStyle(CodyPressableButtonStyle())
                    .accessibilityLabel(Text("Close"))
                }
            }
            .padding(.horizontal, CodySpacing.smPlus)
            .padding(.vertical, CodySpacing.xsPlus)
            .background(isSelected ? CodyColors.bgProgressTrack : CodyColors.bgSecondary, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? CodyColors.textAccent.opacity(0.45) : CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tabLabel(for tab: BrowserTabPool.Tab) -> String {
        let title = tab.manager.pageTitle
        if !title.isEmpty { return String(title.prefix(20)) }
        let url = tab.manager.currentURL
        if !url.isEmpty { return String(url.prefix(20)) }
        return "Tab \(tab.id)"
    }
}

// MARK: - Address Bar Loading Icon

/// Globe icon with a spinning arc border when loading.
private struct BrowserAddressBarIcon: View {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(isLoading ? CodyColors.iconAccent : CodyColors.iconSecondary)
                .accessibilityHidden(true)

            if isLoading {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(CodyColors.iconAccent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(!reduceMotion && spinning ? 360 : 0))
                    .animation(
                        CodyMotion.resolved(.linear(duration: 1).repeatForever(autoreverses: false), reduceMotion: reduceMotion),
                        value: spinning
                    )
                    .onAppear { spinning = true }
                    .onDisappear { spinning = false }
                    .transition(.identity)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Agent Browsing Overlay

/// Breathing-light overlay shown when the agent is controlling the browser.
/// Blocks all user interaction on the webview while providing a visual cue.
private struct AgentBrowsingOverlay: View {
    var onTakeover: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var breathing = false

    var body: some View {
        ZStack {
            // Semi-transparent backdrop that blocks touches
            CodyColors.bgScrim

            // Centered indicator with breathing glow
            HStack(spacing: CodySpacing.md) {
                Circle()
                    .fill(CodyColors.streamingHighlight)
                    .frame(width: CodySpacing.sm, height: CodySpacing.sm)
                    .opacity(!reduceMotion && breathing ? 1.0 : 0.65)
                    .shadow(
                        color: CodyColors.streamingHighlight.opacity(!reduceMotion && breathing ? 0.8 : 0),
                        radius: !reduceMotion && breathing ? 8 : 0
                    )
                    .accessibilityHidden(true)

                Text("Cody is browsing")
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)

                if let onTakeover {
                    Divider()
                        .frame(height: 14)
                        .overlay(CodyColors.interactivePrimaryLabel.opacity(0.3))

                    Button("Takeover") {
                        onTakeover()
                    }
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textAccent)
                    .buttonStyle(CodyPressableButtonStyle())
                }
            }
            .padding(.horizontal, CodySpacing.xl)
            .padding(.vertical, CodySpacing.md)
            .background(
                Capsule()
                    .fill(
                        reduceTransparency
                            ? CodyColors.interactivePrimaryBg
                            : CodyColors.interactivePrimaryBg.opacity(0.88)
                    )
            )
            .overlay {
                Capsule()
                    .strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle()) // capture all touches
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

// MARK: - Download Progress Banner

/// Slim banner listing this session's downloads inside the browser sheet.
/// [T-browser-download-ux] Now driven by the session-scoped
/// BrowserDownloadCenter (covers all tabs) and reuses the same card rows as
/// the chat's floating overlay, so the sheet shows live percent/bytes too.
struct BrowserDownloadBanner: View {
    @ObservedObject var manager: BrowserUseManager
    @ObservedObject private var center = BrowserDownloadCenter.shared

    var body: some View {
        let items = center.downloads(for: manager.sessionIdProvider?() ?? "")
        if !items.isEmpty {
            VStack(spacing: CodySpacing.xsPlus) {
                ForEach(items) { entry in
                    BrowserDownloadCardRow(entry: entry,
                                           onTap: nil,
                                           onDismiss: { center.dismiss(id: entry.id) })
                }
            }
            .padding(.horizontal, CodySpacing.md)
            .padding(.vertical, CodySpacing.sm)
            .background(CodyColors.bgGrouped)
        }
    }
}

// MARK: - Floating download button (chat overlay)

/// Round 36×36 floating button shown near the scroll-jump buttons while the
/// session has active/unviewed native browser downloads. Shares the scroll
/// buttons' surface (`FloatingCircleButtonSurface`: glass on iOS 26+,
/// system-background circle + stroke + shadow below). Badge = in-flight + unviewed terminal entries;
/// hidden entirely at badge 0. Tapping opens BrowserDownloadPanelSheet.
/// [T-browser-download-ux-v2]
struct BrowserDownloadFloatingButton: View {
    @ObservedObject private var center = BrowserDownloadCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sessionId: String
    let action: () -> Void

    @State private var legacyPulse = false

    var body: some View {
        let items = center.downloads(for: sessionId)
        // Visible while ANY entries exist (user hasn't cleared them yet) —
        // the button disappears the moment the last record is cleared. The
        // badge itself only renders when there is something "active" to
        // count (in-flight + unviewed terminal entries).
        if !items.isEmpty {
            let badge = center.badgeCount(for: sessionId)
            let downloading = items.contains { $0.state == .downloading }
            Button(action: action) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FloatingCircleButtonSurface.glyphStyle)
                    .modifier(DownloadPulseModifier(active: downloading, legacyPulse: $legacyPulse))
                    .frame(width: 36, height: 36)
                    .modifier(FloatingCircleButtonSurface(
                        legacyLightOpacity: 0.5,
                        legacyStrokeOpacity: 0.25,
                        legacyShadowOpacity: 0.12,
                        legacyShadowRadius: 4
                    ))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, badge > 9 ? 4 : 0)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.red, in: Capsule())
                                .offset(x: 5, y: -5)
                        }
                    }
            }
            .buttonStyle(CodyPressableButtonStyle())
            .accessibilityLabel(Text("Downloads", comment: "Downloads panel title"))
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

/// Pulse on iOS 17+ via symbolEffect; below that, a gentle repeating opacity
/// breath driven by an explicit animation.
private struct DownloadPulseModifier: ViewModifier {
    let active: Bool
    @Binding var legacyPulse: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)
        } else {
            content
                .opacity(active && !reduceMotion && legacyPulse ? 0.35 : 1.0)
                .animation(
                    active
                        ? CodyMotion.resolved(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), reduceMotion: reduceMotion)
                        : nil,
                    value: legacyPulse
                )
                .onAppear { if active && !reduceMotion { legacyPulse = true } }
                .onChange(of: active) { nowActive in
                    legacyPulse = nowActive && !reduceMotion
                }
        }
    }
}

// MARK: - Downloads panel sheet

/// Download manager panel opened from the floating button: all of the
/// session's downloads newest-first — cancel for in-flight rows, jump to the
/// file browser (located at the file) for completed rows, reason + clear for
/// failed rows. [T-browser-download-ux-v2]
struct BrowserDownloadPanelSheet: View {
    @ObservedObject private var center = BrowserDownloadCenter.shared
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    /// Called with the workspace filename when the user opens a completed row.
    let onLocate: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                let items = center.downloads(for: sessionId)
                    .sorted { $0.startedAt > $1.startedAt }
                if items.isEmpty {
                    VStack(spacing: CodySpacing.md) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(CodyColors.iconTertiary)
                            .frame(width: CodySpacing.s56, height: CodySpacing.s56)
                            .background(
                                CodyColors.bgListIcon,
                                in: RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
                                    .strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                                    .allowsHitTesting(false)
                            }
                            .accessibilityHidden(true)
                        Text("No downloads", comment: "Empty downloads panel")
                            .font(CodyTypography.titleSmall)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CodyColors.bgGrouped)
                } else {
                    List {
                        ForEach(items) { entry in
                            BrowserDownloadPanelRow(
                                entry: entry,
                                onCancel: { center.cancel(id: entry.id) },
                                onLocate: { onLocate(entry.filename) },
                                onClear: { center.dismiss(id: entry.id) }
                            )
                            .codyGroupedRow()
                        }
                    }
                    .codyGroupedListCanvas()
                }
            }
            .navigationTitle(Text("Downloads", comment: "Downloads panel title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // [T-browser-download-ux-v3] "Clear" wipes every finished
                    // record (completed + failed); in-flight rows stay.
                    let hasFinished = center.downloads(for: sessionId).contains {
                        $0.state != .downloading
                    }
                    if hasFinished {
                        Button {
                            center.clearFinished(for: sessionId)
                        } label: {
                            Text("Clear", comment: "Downloads panel action")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(AppLocalized("Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Viewing the panel clears the badge; records themselves persist
        // until the user clears them (rows / Clear Completed) — the floating
        // button hides only when the list is actually empty.
        .onAppear { center.markAllSeen(for: sessionId) }
    }
}

/// One panel row: state icon + filename + progress/summary, with a
/// state-appropriate trailing action (cancel / locate chevron / clear).
private struct BrowserDownloadPanelRow: View {
    let entry: BrowserDownloadCenter.Entry
    let onCancel: () -> Void
    let onLocate: () -> Void
    let onClear: () -> Void
    @StateObject private var progress: DownloadProgressObserver

    init(entry: BrowserDownloadCenter.Entry,
         onCancel: @escaping () -> Void,
         onLocate: @escaping () -> Void,
         onClear: @escaping () -> Void) {
        self.entry = entry
        self.onCancel = onCancel
        self.onLocate = onLocate
        self.onClear = onClear
        _progress = StateObject(wrappedValue: DownloadProgressObserver(progress: entry.progress))
    }

    var body: some View {
        HStack(spacing: CodySpacing.md) {
            stateIcon
                .font(.system(size: 24))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CodySpacing.xs) {
                Text(entry.filename)
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch entry.state {
                case .downloading:
                    let done = ByteCountFormatter.string(fromByteCount: progress.completed, countStyle: .file)
                    let pctText = progress.total > 0 ? "\(Int(progress.fraction * 100))% · " : ""
                    let totalText = progress.total > 0
                        ? " / \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))" : ""
                    Text("\(pctText)\(done)\(totalText)")
                        .font(CodyTypography.bodySmall)
                        .monospacedDigit()
                        .foregroundStyle(CodyColors.textSecondary)
                    CodyProgressBar(progress: progress.fraction)
                case .completed(let sizeText):
                    Text("\(sizeText) · \(AppLocalized("Show in Files", comment: "Completed download row hint"))")
                        .font(CodyTypography.bodySmall)
                        .monospacedDigit()
                        .foregroundStyle(CodyColors.textSecondary)
                case .failed(let reason):
                    Text(reason)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.statusErrorText)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            switch entry.state {
            case .downloading:
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(CodyColors.iconSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Cancel"))
            case .completed:
                Image(systemName: "chevron.right")
                    .font(.system(size: CodyMetrics.Settings.disclosureSize, weight: .semibold))
                    .foregroundStyle(CodyColors.iconDisclosure)
                    .accessibilityHidden(true)
            case .failed:
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(CodyColors.iconSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear", comment: "Downloads panel action"))
            }
        }
        .padding(.vertical, CodySpacing.xsPlus)
        .contentShape(Rectangle())
        .onTapGesture {
            if case .completed = entry.state { onLocate() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if entry.state != .downloading {
                Button(role: .destructive, action: onClear) {
                    Label(AppLocalized("Clear"), systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch entry.state {
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(CodyColors.iconAccent)
                .symbolEffectPulseIfAvailable()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CodyColors.connectionReady)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(CodyColors.statusErrorText)
        }
    }
}

/// One download card: state icon + filename + live progress (percent and
/// downloaded/total bytes) or completion/failure summary. Completed cards
/// are tappable (open the file preview).
struct BrowserDownloadCardRow: View {
    let entry: BrowserDownloadCenter.Entry
    let onTap: (() -> Void)?
    let onDismiss: (() -> Void)?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var progress: DownloadProgressObserver

    init(entry: BrowserDownloadCenter.Entry,
         onTap: (() -> Void)?,
         onDismiss: (() -> Void)?) {
        self.entry = entry
        self.onTap = onTap
        self.onDismiss = onDismiss
        _progress = StateObject(wrappedValue: DownloadProgressObserver(progress: entry.progress))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
        HStack(spacing: CodySpacing.smPlus) {
            stateIcon
                .font(.system(size: 22))
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(entry.filename)
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
                if case .downloading = entry.state {
                    CodyProgressBar(progress: progress.fraction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CodyColors.iconSecondary)
                        .padding(CodySpacing.xsPlus)
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .padding(.horizontal, CodySpacing.md)
        .padding(.vertical, CodySpacing.smPlus)
        .background {
            if reduceTransparency {
                shape.fill(CodyColors.bgElevatedPrimary)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    @ViewBuilder private var stateIcon: some View {
        switch entry.state {
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(CodyColors.iconAccent)
                .symbolEffectPulseIfAvailable()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CodyColors.connectionReady)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(CodyColors.statusErrorText)
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch entry.state {
        case .downloading:
            let done = ByteCountFormatter.string(fromByteCount: progress.completed, countStyle: .file)
            let pctText = progress.total > 0 ? "\(Int(progress.fraction * 100))% · " : ""
            let totalText = progress.total > 0
                ? " / \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))" : ""
            Text("\(pctText)\(done)\(totalText)")
                .font(CodyTypography.bodySmall)
                .monospacedDigit()
                .foregroundStyle(CodyColors.textSecondary)
        case .completed(let sizeText):
            Text("\(sizeText) · \(AppLocalized("Tap to view", comment: "Completed download card"))")
                .font(CodyTypography.bodySmall)
                .monospacedDigit()
                .foregroundStyle(CodyColors.textSecondary)
        case .failed(let reason):
            Text(reason)
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.statusErrorText)
                .lineLimit(2)
        }
    }
}

private extension View {
    /// Gentle pulse on the in-progress icon where the OS supports it.
    @ViewBuilder func symbolEffectPulseIfAvailable() -> some View {
        if #available(iOS 17, *) {
            self.symbolEffect(.pulse)
        } else {
            self
        }
    }
}

/// KVO bridge: republishes a WKDownload's NSProgress (fractionCompleted /
/// byte counts) on the main thread so SwiftUI text refreshes live — a bare
/// `Progress` held in a struct is not observed by SwiftUI for Text purposes.
final class DownloadProgressObserver: ObservableObject {
    @Published var fraction: Double
    @Published var completed: Int64
    @Published var total: Int64
    private var observation: NSKeyValueObservation?

    init(progress: Progress) {
        fraction = progress.fractionCompleted
        completed = progress.completedUnitCount
        total = progress.totalUnitCount
        // fractionCompleted changes whenever completed/total unit counts do,
        // so one observation covers all three published values.
        observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.fraction = p.fractionCompleted
                self?.completed = p.completedUnitCount
                self?.total = p.totalUnitCount
            }
        }
    }
}

/// [T-ios-webview-error-ui] Observes the manager's `loadError` and renders the
/// shared Safari-style overlay (with Retry) over the agent browser's blank
/// page. Split into its own `@ObservedObject` view so a `loadError` change
/// actually re-renders — the parent reads `manager` via a computed property and
/// wouldn't otherwise observe it.
private struct BrowserLoadErrorOverlay: View {
    @ObservedObject var manager: BrowserUseManager

    var body: some View {
        if let err = manager.loadError {
            WebLoadErrorOverlay(error: err) { manager.retryFailedLoad() }
        }
    }
}
