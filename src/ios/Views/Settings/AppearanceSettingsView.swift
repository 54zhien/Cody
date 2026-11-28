//
//  AppearanceSettingsView.swift
//  Cody - home screen (session list, navigation, settings entry)
//
//  Settings > Appearance: theme, app icon, language (supportedLanguages - also
//  edited by scripts/register_locale.py), font scale and related toggles.
//  Opened from SettingsSheet.
//
//  Map of the ContentView files: ContentView/ContentView.swift.
//

import SwiftUI

// MARK: - Appearance Settings

private struct AppIconOption: Identifiable {
    let id: Int
    let title: String
    let iconName: String?  // nil = automatic (default asset catalog icon)
    let imageName: String  // bundle image file name for preview
}

private struct LanguageOption: Identifiable {
    let id: String   // language code, "" = system
    let name: String  // native name
    let flag: String
}

// Native names are deliberately NOT localized: a language picker shows each
// option in its own language so a user who cannot read the current UI language
// can still find theirs.
//
// [T-ios-inapp-language-string-localized] zh-Hant was missing even though the
// catalog carries a full Traditional Chinese translation, so those users could
// not select it in-app; es is new. Every id here must have a matching .lproj in
// the bundle — `Bundle.setLanguage(_:)` looks the directory up by this string
// and silently falls back to the system language if it is absent.
private let supportedLanguages: [LanguageOption] = [
    LanguageOption(id: "",       name: "System", flag: ""),
    LanguageOption(id: "en",     name: "English", flag: "🇺🇸"),
    LanguageOption(id: "zh-Hans", name: "简体中文", flag: "🇨🇳"),
    LanguageOption(id: "zh-Hant", name: "繁體中文", flag: "🇭🇰"),
    LanguageOption(id: "ja",     name: "日本語", flag: "🇯🇵"),
    LanguageOption(id: "ko",     name: "한국어", flag: "🇰🇷"),
    LanguageOption(id: "es",     name: "Español", flag: "🇪🇸"),
    LanguageOption(id: "fr",     name: "Français", flag: "🇫🇷"),
    LanguageOption(id: "de",     name: "Deutsch", flag: "🇩🇪"),
    LanguageOption(id: "ru",     name: "Русский", flag: "🇷🇺"),
    LanguageOption(id: "id",     name: "Bahasa Indonesia", flag: "🇮🇩"),
    LanguageOption(id: "ms",    name: "Bahasa Melayu", flag: "🇲🇾"),
    LanguageOption(id: "fil",   name: "Filipino", flag: "🇵🇭"),
    LanguageOption(id: "th",    name: "ไทย", flag: "🇹🇭"),
    LanguageOption(id: "tr",    name: "Türkçe", flag: "🇹🇷"),
    LanguageOption(id: "pl",    name: "Polski", flag: "🇵🇱"),
    LanguageOption(id: "ro",    name: "Română", flag: "🇷🇴"),
    LanguageOption(id: "pt-BR", name: "Português (Brasil)", flag: "🇧🇷"),
    LanguageOption(id: "hr",    name: "Hrvatski", flag: "🇭🇷"),
]

private struct FontScaleRow: View {
    let label: String
    @Binding var level: FontScaleLevel

    private static let cases = FontScaleLevel.allCases
    private var currentIndex: Int {
        Self.cases.firstIndex(of: level) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CodySpacing.xsPlus) {
            Text(LocalizedStringKey(label))
                .font(CodyTypography.titleMedium)
                .foregroundStyle(CodyColors.textPrimary)

            HStack(spacing: CodySpacing.sm) {
                stepButton(offset: -1, title: "Decrease Font Size", font: CodyTypography.labelLarge)
                    .disabled(currentIndex == 0)

                SteppedSlider(value: currentIndex, steps: Self.cases.count, onChanged: select)
                    .accessibilityLabel(Text(LocalizedStringKey(label)))
                    .accessibilityValue(Text(LocalizedStringKey(level.label)))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: select(currentIndex + 1)
                        case .decrement: select(currentIndex - 1)
                        @unknown default: break
                        }
                    }

                stepButton(offset: 1, title: "Increase Font Size", font: CodyTypography.headlineSmall)
                    .disabled(currentIndex == Self.cases.count - 1)
            }
        }
        .padding(.vertical, CodySpacing.xs)
    }

    private func select(_ index: Int) {
        guard Self.cases.indices.contains(index), level != Self.cases[index] else { return }
        level = Self.cases[index]
    }

    private func stepButton(offset: Int, title: LocalizedStringKey, font: Font) -> some View {
        Button {
            select(currentIndex + offset)
        } label: {
            Text("A")
                .font(font)
                .foregroundStyle(CodyColors.textSecondary)
                .frame(minWidth: CodyControlHeight.standard, minHeight: CodyControlHeight.standard)
                .background(CodyColors.interactiveSecondaryBg, in: RoundedRectangle(cornerRadius: CodyRadius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(CodyPressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

/// A custom stepped slider that supports both drag and tap-to-snap.
/// Uses local gesture state to avoid layout feedback loops from SwiftUI's Slider.
private struct SteppedSlider: View {
    let value: Int
    let steps: Int
    let onChanged: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let trackHeight = CodyRadius.xs
    private let thumbSize: CGFloat = 22
    private let tickSize = CodySpacing.xsPlus

    @State private var dragValue: Int?

    private var displayValue: Int { dragValue ?? value }

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let midY = geo.size.height / 2
            let inset = min(thumbSize / 2, totalW / 2)
            let trackWidth = totalW - 2 * inset
            let maxStep = CGFloat(steps - 1)

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(reduceTransparency ? CodyColors.interactiveControlDefault : CodyColors.bgProgressTrack)
                    .frame(width: trackWidth, height: trackHeight)
                    .position(x: totalW / 2, y: midY)

                // Filled portion
                let fillW = maxStep > 0 ? trackWidth * CGFloat(displayValue) / maxStep : 0
                Capsule()
                    .fill(CodyColors.interactiveProgressFill)
                    .frame(width: fillW, height: trackHeight)
                    .position(x: inset + fillW / 2, y: midY)

                // Tick marks
                ForEach(0..<steps, id: \.self) { i in
                    let x = inset + (maxStep > 0 ? trackWidth * CGFloat(i) / maxStep : 0)
                    Circle()
                        .fill(i <= displayValue ? CodyColors.interactiveProgressFill : CodyColors.interactiveControlDefault)
                        .frame(width: tickSize, height: tickSize)
                        .position(x: x, y: midY)
                }

                // Thumb
                let thumbX = inset + fillW
                Circle()
                    .fill(CodyColors.bgCanvas)
                    .overlay { Circle().strokeBorder(CodyColors.borderHeavy, lineWidth: CodySpacing.px) }
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: thumbX, y: midY)
            }
            .accessibilityElement(children: .ignore)
            .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: displayValue)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let step = stepFromX(drag.location.x - inset, width: trackWidth)
                        if step != dragValue { dragValue = step }
                    }
                    .onEnded { drag in
                        let step = stepFromX(drag.location.x - inset, width: trackWidth)
                        onChanged(step)
                        dragValue = nil
                    }
            )
        }
        .frame(height: CodyControlHeight.standard)
    }

    private func stepFromX(_ x: CGFloat, width: CGFloat) -> Int {
        guard width > 0, steps > 1 else { return 0 }
        let fraction = x / width
        let clamped = min(max(fraction, 0), 1)
        return Int((clamped * CGFloat(steps - 1)).rounded())
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("appIconMode") private var appIconMode: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = ""
    @AppStorage("launchScreen") private var launchScreen: Int = 0  // 0=Auto, 1=Last Session, 2=New Chat, 3=Home
    @AppStorage("toolPreviewEnabled") private var toolPreviewEnabled: Bool = true
    /// 0 = Return inserts a newline (default), 1 = Return sends the message.
    @AppStorage("returnKeyBehavior") private var returnKeyBehavior: Int = 0
    /// [T-keyboard-auto-pop default flip] When true, the input field becomes
    /// the first responder ~1.5 s after the model finishes a reply (the
    /// historical behavior). ON by default — most users want the composer
    /// ready for a follow-up immediately. Existing users who explicitly
    /// toggled OFF keep their stored false; users who never opened the
    /// toggle get the new ON default via @AppStorage's fallback.
    @AppStorage("chat.autoFocusAfterReply") private var autoFocusAfterReply: Bool = true
    /// [T-stop-confirm] Ask before the composer's stop button stops a running
    /// task. Read by ChatSendButton through `StopConfirmPolicy.settingsKey`;
    /// [T-stop-mode-longpress] OFF by default, also set from the stop button's long-press.
    @AppStorage(StopConfirmPolicy.settingsKey) private var confirmBeforeStopping: Bool = StopConfirmPolicy.defaultValue
    /// [T-thinking-auto-expand-toggle] When true (default, historical
    /// behavior) a NEW streaming thinking block auto-expands while reasoning
    /// streams. When false it stays collapsed until tapped. Read at
    /// block-mount time in ThinkingBlockView.
    @AppStorage("chat.autoExpandThinking") private var autoExpandThinking: Bool = true
    /// [T-fold-consecutive-tools] Mirrors `ToolFoldPlanner.settingsKey`.
    @AppStorage("chat.foldConsecutiveTools") private var foldConsecutiveTools: Bool = false
    @ObservedObject private var fontSettings = FontSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private let iconOptions: [AppIconOption] = [
        AppIconOption(id: 0, title: "Automatic", iconName: nil, imageName: "LadySereneIconLight"),
        AppIconOption(id: 1, title: "Light", iconName: "AppIcon-Light", imageName: "LadySereneIconLight"),
        AppIconOption(id: 2, title: "Dark", iconName: "AppIcon-Dark", imageName: "LadySereneIconDark"),
    ]

    var body: some View {
        CodySettingsScrollPage {
            themeSection
            displaySection
            fontSection
            launchSection
            chatSections
            SettingsKeepAwakeSection()
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .background(InteractivePopGestureDisabler())
    }

    private var themeSection: some View {
        CodySettingsNovaSection(footer: UIApplication.shared.supportsAlternateIcons
            ? "\"Automatic\" uses the system icon which adapts to Dark Mode on iOS 18+."
            : nil) {
            Menu {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
            } label: {
                SettingsNovaPickerLabel(title: "Appearance", value: Text(appearanceLabel))
            }
            .buttonStyle(CodyPressableButtonStyle())

            if UIApplication.shared.supportsAlternateIcons {
                CodySettingsNovaDivider(leadingInset: 18)
                appIconPicker
            }
        }
        .onChange(of: appearanceMode) { _ in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = appearanceMode == 1 ? .light : appearanceMode == 2 ? .dark : .unspecified
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

    private var appIconPicker: some View {
        let current = iconOptions.first { $0.id == appIconMode } ?? iconOptions[0]
        let previewName = current.iconName == nil && colorScheme == .dark
            ? "LadySereneIconDark"
            : current.imageName
        return Menu {
            Picker("App Icon", selection: Binding(get: { appIconMode }, set: changeAppIcon)) {
                ForEach(iconOptions) { option in
                    Text(LocalizedStringKey(option.title)).tag(option.id)
                }
            }
        } label: {
            CodySettingsNovaRowContent(title: "App Icon", subtitle: nil, systemImage: nil, tint: nil, showsDisclosure: false) {
                if let image = UIImage(named: previewName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: CodyRadius.sm, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(current.title))
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                SettingsNovaDisclosure(systemImage: "chevron.up.chevron.down")
            }
        }
        .buttonStyle(CodyPressableButtonStyle())
    }

    private func changeAppIcon(_ id: Int) {
        guard let option = iconOptions.first(where: { $0.id == id }) else { return }
        let application = UIApplication.shared
        guard application.alternateIconName != option.iconName else {
            appIconMode = id
            return
        }
        application.setAlternateIconName(option.iconName) { error in
            if let error {
                print("[AppIcon] Failed to set icon: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async { appIconMode = id }
        }
    }

    private var languagePicker: some View {
        Menu {
            Picker("Language", selection: Binding(get: { appLanguage }, set: changeLanguage)) {
                ForEach(supportedLanguages) { lang in
                    if lang.flag.isEmpty {
                        Text("System").tag(lang.id)
                    } else {
                        Text("\(lang.flag) \(lang.name)").tag(lang.id)
                    }
                }
            }
        } label: {
            CodySettingsNovaRowContent(title: "App Language", subtitle: nil, systemImage: nil, tint: nil) {
                Text(verbatim: languageLabel)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
            }
        }
        .buttonStyle(CodyPressableButtonStyle())
    }

    private var languageLabel: String {
        guard let language = supportedLanguages.first(where: { $0.id == appLanguage }),
              !language.id.isEmpty else { return AppLocalized("System") }
        return language.name
    }

    private func changeLanguage(_ id: String) {
        guard appLanguage != id else { return }
        // Save the return destination and keep active agents alive across the root language remount.
        UserDefaults.standard.set("appearance", forKey: "pendingSettingsReopen")
        ViewModelCache.shared.suspendAllForTreeRemount()
        appLanguage = id
        Bundle.setLanguage(id.isEmpty ? nil : id)
    }

    private var fontSection: some View {
        CodySettingsNovaSection(
            "Font Scale",
            footer: "Scale fonts for chat input, message content, and general app text. Changes apply immediately."
        ) {
            FontScaleRow(label: "Chat Input", level: $fontSettings.chatInputScale)
                .settingsNovaControlRow()
            CodySettingsNovaDivider(leadingInset: 18)
            FontScaleRow(label: "Message Text", level: $fontSettings.messageBaseScale)
                .settingsNovaControlRow()
            CodySettingsNovaDivider(leadingInset: 18)
            FontScaleRow(label: "App Base", level: $fontSettings.appBaseScale)
                .settingsNovaControlRow()
            if fontSettings.isModified {
                CodySettingsNovaDivider(leadingInset: 18)
                CodySettingsNovaActionRow("Reset to Defaults", isDestructive: true) {
                    fontSettings.resetToDefaults()
                }
            }
        }
    }

    private var launchSection: some View {
        CodySettingsNovaSection(
            footer: "Choose what to show when the app starts. \"Auto\" opens a new chat if the last session is older than 15 minutes."
        ) {
            Menu {
                Picker("Launch Session", selection: $launchScreen) {
                    Text("Auto").tag(0)
                    Text("Last Session").tag(1)
                    Text("New Chat").tag(2)
                    Text("Home").tag(3)
                }
            } label: {
                SettingsNovaPickerLabel(title: "Launch Session", value: Text(launchScreenLabel))
            }
            .buttonStyle(CodyPressableButtonStyle())
        }
    }

    private var launchScreenLabel: LocalizedStringKey {
        switch launchScreen {
        case 1: "Last Session"
        case 2: "New Chat"
        case 3: "Home"
        default: "Auto"
        }
    }

    @ViewBuilder
    private var chatSections: some View {
        CodySettingsNovaSection(
            "Grouping",
            footer: "When a chat's title is first generated, also file it into a matching existing group. Runs once per chat, only uses groups you already created, and leaves the chat ungrouped when nothing matches."
        ) {
            Toggle("Auto-Grouping", isOn: autoGroupingBinding)
                .tint(.green)
                .settingsNovaControlRow()
        }

        CodySettingsNovaSection(
            "Return Key",
            footer: "Choose whether the Return key in the chat input inserts a newline or sends the message. Hardware Shift+Return always inserts a newline."
        ) {
            Picker(AppLocalized("Return Key"), selection: $returnKeyBehavior) {
                Text(AppLocalized("Newline")).tag(0)
                Text(AppLocalized("Send")).tag(1)
            }
            .pickerStyle(.segmented)
            .settingsNovaControlRow()
        }
    }

    private var displaySection: some View {
        CodySettingsNovaSection(footer: "Override the display language for this app. \"System\" follows your device language.") {
            languagePicker
            CodySettingsNovaDivider(leadingInset: 18)
            displayToggle(description: "When on, the keyboard pops up automatically after the model finishes replying so the input is ready for a follow-up. On by default; turn off if you prefer to read the response without an unexpected keyboard.") {
                Toggle(AppLocalized("Auto-Focus Input After Reply"), isOn: $autoFocusAfterReply)
            }
            CodySettingsNovaDivider(leadingInset: 18)
            displayToggle(description: "Ask for confirmation when you tap the stop button while a task is running, so an accidental tap does not end a long run. Off by default. You can also long-press the stop button to switch.") {
                Toggle(AppLocalized("Confirm Before Stopping"), isOn: $confirmBeforeStopping)
            }
            CodySettingsNovaDivider(leadingInset: 18)
            displayToggle(description: "Show a live preview thumbnail alongside the tool status bar during agent execution.") {
                Toggle(AppLocalized("Tool Preview Window"), isOn: $toolPreviewEnabled)
            }
            CodySettingsNovaDivider(leadingInset: 18)
            displayToggle(description: "When on, a new thinking block expands automatically while the model is reasoning and collapses when it finishes. When off, thinking blocks stay collapsed — tap one to read it.") {
                Toggle(AppLocalized("Expand Thinking While Streaming"), isOn: $autoExpandThinking)
            }
            CodySettingsNovaDivider(leadingInset: 18)
            displayToggle(description: "Consecutive tool calls are shown as one line. Tap it to see each call.") {
                Toggle(AppLocalized("Fold Consecutive Tool Calls"), isOn: $foldConsecutiveTools)
                    .onChange(of: foldConsecutiveTools) { _ in
                        NotificationCenter.default.post(name: .messageListNeedsResnapshot, object: nil)
                    }
            }
        }
    }

    private func displayToggle<Control: View>(
        description: LocalizedStringKey,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.xs) {
            control()
                .tint(.green)
            Text(description)
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
        }
        .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
    }

    /// UserDefaults-backed binding (not @AppStorage: the key is read at
    /// title-generation time in AIChatViewModel, so a plain defaults write is
    /// the single source of truth).
    private var autoGroupingBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: "autoGroupingEnabled") },
            set: { UserDefaults.standard.set($0, forKey: "autoGroupingEnabled") }
        )
    }
}

struct SettingsKeepAwakeSection: View {
    /// When true, holds `UIApplication.isIdleTimerDisabled` while any session
    /// is running a task. See `KeepScreenAwakeController`.
    @AppStorage("keepScreenAwakeDuringTasks") private var keepScreenAwakeDuringTasks: Bool = false
    /// [T-always-on-idle-setting] Screen Saver: seconds without a touch before
    /// the black screen, 0 = Off (default). See `AlwaysOnController.idleDelay`.
    @AppStorage(AlwaysOnController.idleSecondsKey) private var alwaysOnIdleSeconds: Int = 0

    /// Settings' choices, plus a value set from `cody-config` that is not one
    /// of them, so the picker never shows an empty selection.
    private var screenSaverChoices: [Int] {
        let base = AlwaysOnController.idleChoices
        return base.contains(alwaysOnIdleSeconds) ? base : (base + [alwaysOnIdleSeconds]).sorted()
    }

    private static func screenSaverLabel(_ seconds: Int) -> String {
        switch seconds {
        case ..<1: return AppLocalized("Off")
        case 30: return AppLocalized("After 30 Seconds")
        case 60: return AppLocalized("After 1 Minute")
        case 120: return AppLocalized("After 2 Minutes")
        case 300: return AppLocalized("After 5 Minutes")
        default: return String(format: AppLocalized("After %d Seconds"), seconds)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CodySpacing.sm) {
            CodySettingsNovaSection("Keep Screen Awake") {
                Toggle(AppLocalized("Keep Screen Awake"), isOn: $keepScreenAwakeDuringTasks)
                    .tint(.green)
                    .settingsNovaControlRow()
                if keepScreenAwakeDuringTasks {
                    Picker(AppLocalized("Screen Saver"), selection: $alwaysOnIdleSeconds) {
                        ForEach(screenSaverChoices, id: \.self) { seconds in
                            Text(Self.screenSaverLabel(seconds)).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(CodyColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .overlay(alignment: .leading) {
                        Text(AppLocalized("Screen Saver"))
                            .font(CodyTypography.bodyLarge)
                            .foregroundStyle(CodyColors.textPrimary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .settingsNovaControlRow()
                    .overlay(alignment: .top) {
                        CodySettingsNovaDivider(leadingInset: 18)
                    }
                }
            }
            VStack(alignment: .leading, spacing: CodySpacing.xs) {
                Text("Prevent the screen from sleeping while any session is running a task. May increase battery drain.")
                Text("Screen Saver: after the chosen time without a touch, the chat on screen turns black and shows only the current step; tap anywhere to return. Staying in the foreground helps tasks run faster. Use “Keep Screen On” in a chat's … menu to turn it on or off for that chat only.")
            }
            .settingsNovaFooter()
        }
    }
}

/// Disables the navigation controller's interactive pop gesture on the hosting page
/// to prevent conflict with horizontal Slider drag.
private struct InteractivePopGestureDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = GestureDisablerView()
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private class GestureDisablerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            setPopGesture(enabled: false)
        }
        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil { setPopGesture(enabled: true) }
        }
        private func setPopGesture(enabled: Bool) {
            // Walk the responder chain to find the UINavigationController
            var responder: UIResponder? = self
            while let r = responder {
                if let nav = r as? UINavigationController {
                    nav.interactivePopGestureRecognizer?.isEnabled = enabled
                    return
                }
                responder = r.next
            }
        }
    }
}
