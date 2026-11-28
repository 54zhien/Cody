import SwiftUI
import PhotosUI

/// Settings page for SOUL.md — Cody's persistent personality file.
/// Opened by the identity card in Settings.
struct SoulSettingsView: View {
    @State private var name: String = SoulMetadata.default.name
    /// Raw emoji value loaded from SOUL.md. Not user-editable; preserved
    /// verbatim on save so we don't rewrite a value the user (or another
    /// device) may have set in the file. UI always shows `displayEmoji`.
    @State private var rawEmoji: String = SoulMetadata.default.emoji
    /// [T-soul-custom-icon] The user's identity icon: an emoji, a
    /// `data:image/png;base64,…` URI, or empty for the default sparkle.
    @State private var icon: String = SoulMetadata.default.icon
    @State private var showIconOptions = false
    @State private var showEmojiPrompt = false
    @State private var emojiDraft = ""
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var iconError: String? = nil
    @State private var style: String = SoulMetadata.default.style
    @State private var lang: String = SoulMetadata.default.lang
    @State private var bodyText: String = ""
    @State private var saveError: String? = nil
    @State private var didJustSave: Bool = false
    @State private var showRestoreConfirm: Bool = false
    @State private var showForceSyncDone: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var loadedRef = LoadedFileRef()
    /// Mirrors `SyncV2Bootstrap.isEnabled` so the Force iCloud Sync row
    /// shows / hides reactively when the user toggles iCloud sync in
    /// Settings. Same pattern as SkillDetailView (#440 / 3a4fe546).
    @AppStorage("cloudSync.v2.enabled") private var iCloudSyncEnabled: Bool = false

    private static var langOptions: [(label: String, value: String)] {
        [
            (AppLocalized("Auto"), "auto"),
            (AppLocalized("Chinese"), "zh"),
            (AppLocalized("English"), "en"),
        ]
    }

    var body: some View {
        CodySettingsScrollPage {
            CodySettingsNovaSection {
                previewCard
                    .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
            }

            CodySettingsNovaSection("Identity") {
                LabeledContent(AppLocalized("Name")) {
                    TextField("Cody", text: $name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityLabel(Text("Name"))
                }
                .settingsNovaControlRow()
                CodySettingsNovaDivider(leadingInset: CodySpacing.lg)
                LabeledContent(AppLocalized("Style")) {
                    TextField(AppLocalized("e.g. Warm, direct, opinionated"), text: $style)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(Text("Style"))
                }
                .settingsNovaControlRow()
                CodySettingsNovaDivider(leadingInset: CodySpacing.lg)
                Picker(AppLocalized("Language"), selection: $lang) {
                    ForEach(Self.langOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .pickerStyle(.menu)
                .settingsNovaControlRow()
            }

            VStack(alignment: .leading, spacing: CodySpacing.sm) {
                CodySettingsNovaSection("Personality Prompt") {
                    personalityEditor
                        .settingsNovaControlRow()
                }
                bodyLengthFooter
                    .settingsNovaFooter()
            }

            CodySettingsNovaSection {
                CodySettingsNovaActionRow("Restore Default", systemImage: "arrow.uturn.backward", isDestructive: true) {
                    showRestoreConfirm = true
                }

                if #available(iOS 17.0, *), iCloudSyncEnabled {
                    CodySettingsNovaDivider()
                    CodySettingsNovaActionRow("Force iCloud Sync", systemImage: "icloud.and.arrow.up", tint: .blue, action: {
                        Task { await forceSyncSoul() }
                    }) {
                        if showForceSyncDone {
                            Text("Queued")
                                .foregroundStyle(CodyColors.statusSuccessText)
                                .font(CodyTypography.bodySmall)
                        }
                    }
                }
            }

            if let saveError {
                CodySettingsNovaSection {
                    Text(saveError)
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.statusErrorText)
                        .settingsNovaControlRow()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(AppLocalized("Soul"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalized("Save")) { save() }
                    .disabled(!isDirty || isBodyOverLimit)
            }
        }
        .onAppear(perform: reload)
        // Using .alert (not .confirmationDialog) so the dialog stays
        // centered on iPad / Mac. confirmationDialog without a source
        // rect renders as a popover anchored to the screen's top edge
        // on regular-width size classes.
        .alert(
            AppLocalized("Restore Default"),
            isPresented: $showRestoreConfirm
        ) {
            Button(AppLocalized("Restore Default"), role: .destructive, action: restoreDefault)
            Button(AppLocalized("Cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalized("Restore default SOUL.md? Your current personality will be replaced."))
        }
        .modifier(SoulIconEditing(
            icon: $icon,
            showEmojiPrompt: $showEmojiPrompt,
            emojiDraft: $emojiDraft,
            showPhotoPicker: $showPhotoPicker,
            photoItem: $photoItem,
            iconError: $iconError
        ))
        .overlay(alignment: .bottom) {
            if didJustSave {
                Text(AppLocalized("Saved"))
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.interactivePrimaryLabel)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.vertical, CodySpacing.smPlus)
                    .background(CodyColors.interactivePrimaryBg, in: Capsule())
                    .padding(.bottom, CodySpacing.xxl)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }

    // MARK: - Subviews

    private var previewCard: some View {
        HStack(alignment: .center, spacing: 12) {
            // [T-soul-custom-icon] Tappable, and it has to LOOK tappable: a
            // bare glyph sitting on the card reads as decoration, and the
            // pencil badge alone was too easy to miss. A filled circle gives
            // the icon a defined edge and a hit area the eye can find, which
            // is the same treatment the category badges elsewhere in Settings
            // use. It doubles as a backdrop for transparent PNG icons, whose
            // whole point is having no background of their own.
            Button {
                showIconOptions = true
            } label: {
                // Inset inside the 52pt button so the grey disc stays visible
                // as a ring even when the icon is an image, which otherwise
                // fills the whole frame and hides the affordance entirely.
                SoulIconView(icon: icon, size: SoulIconImage.renderPoints)
                    .frame(width: 44, height: 44)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(CodyColors.bgListIcon))
                    .overlay(
                        Circle().strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                    )
                    // The badge sits INSIDE the circle's bounds rather than
                    // straddling its edge. Overhanging it (even with padding)
                    // gets clipped to a sliver by the enclosing Button label,
                    // which is what made the pencil hard to see.
                    //
                    // Drawn as an explicit filled Circle + pencil glyph rather
                    // than `pencil.circle.fill` with .palette: that symbol's
                    // "circle" layer is the BACKGROUND, so on the white card it
                    // rendered as an invisible disc with a bare diagonal stroke
                    // floating over it. Compositing it ourselves also lets the
                    // badge keep a contrasting ring against a dark icon image.
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CodyColors.interactivePrimaryLabel)
                            .frame(width: 18, height: 18)
                            .background(CodyColors.interactivePrimaryBg, in: Circle())
                            .overlay(Circle().strokeBorder(CodyColors.bgGroupedSurface, lineWidth: CodySpacing.px))
                            .accessibilityHidden(true)
                    }
            }
            .buttonStyle(CodyPressableButtonStyle())
            .accessibilityLabel(AppLocalized("Change icon"))
            // [T-soul-custom-icon] Attached to the BUTTON, not to the whole
            // page. A confirmationDialog anchors its popover to the view it
            // is attached to, so hanging it off the Form (as this first did)
            // pointed the arrow at the middle of the page — visibly at the
            // Style row — instead of at the icon the user tapped. Only the
            // dialog needs the anchor; the alerts and the photo picker are
            // centered/full-screen and stay at page level.
            .confirmationDialog(AppLocalized("Change icon"), isPresented: $showIconOptions) {
                Button(AppLocalized("Choose Emoji…")) {
                    emojiDraft = (icon.isEmpty || SoulIconImage.isDataURI(icon)) ? "" : icon
                    showEmojiPrompt = true
                }
                Button(AppLocalized("Choose Image…")) { showPhotoPicker = true }
                if !icon.isEmpty {
                    Button(AppLocalized("Use Default"), role: .destructive) { icon = "" }
                }
                Button(AppLocalized("Cancel"), role: .cancel) {}
            } message: {
                // [T-soul-icon-opaque-rounded] Any image works. This used to
                // demand a transparent PNG, which stopped being true when the
                // alpha-channel rejection was dropped (fe2f3ae8b) — the icon is
                // drawn with rounded corners, so an opaque photo reads as a
                // normal avatar. `SoulIconImage.RejectionReason` now has one
                // case, `unreadable`, and nothing checks for transparency.
                Text(AppLocalized("Any image works. It's cropped to a square and shown with rounded corners."))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Cody" : name)
                    .font(CodyTypography.titleLarge)
                if !style.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(style)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var personalityEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $bodyText)
                .frame(minHeight: 220)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .accessibilityLabel(Text(AppLocalized("Personality Prompt")))
            // SwiftUI's TextEditor has no native placeholder. We render
            // a greyed hint on top when the body is empty + not being
            // typed into. allowsHitTesting(false) so taps fall through
            // to the editor below.
            if bodyText.isEmpty {
                Text(AppLocalized("Describe the personality and voice you want for your agent"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Footer under the personality editor. Renders a green count when the
    /// body is within budget and a red over-limit message when it isn't.
    /// Save is disabled in the over-limit branch.
    private var bodyLengthFooter: some View {
        let check = SoulStore.isOverLimit(bodyText)
        return HStack(spacing: 6) {
            if check.isOverLimit {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CodyColors.statusErrorText)
                    .accessibilityHidden(true)
            }
            switch check {
            case .ok:
                Text(soulBodyCountText(bodyText))
                    .foregroundStyle(.secondary)
            case .overLimit(let count, let cap):
                Text(AppLocalized("Over limit: \(count) / \(cap) tokens. Each CJK character and each Latin word counts as one."))
                    .foregroundStyle(CodyColors.statusErrorText)
            }
        }
        .font(.footnote)
    }

    /// Counter shown when the body is within budget.
    private func soulBodyCountText(_ body: String) -> String {
        let count = SoulStore.tokenCount(body)
        return AppLocalized("\(count) / \(SoulStore.bodyTokenLimit) tokens")
    }

    private var isBodyOverLimit: Bool {
        SoulStore.isOverLimit(bodyText).isOverLimit
    }

    // MARK: - Persistence

    private var currentFile: SoulFile {
        SoulFile(
            metadata: SoulMetadata(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                // Round-trip the on-disk emoji untouched — UI no longer
                // edits this field, but a SOUL.md authored elsewhere
                // (other device / hand-edit) should not have its emoji
                // rewritten on save.
                emoji: rawEmoji,
                style: style,
                lang: lang,
                icon: icon
            ),
            body: bodyText
        )
    }

    private var isDirty: Bool {
        currentFile != loadedRef.value
    }

    private func reload() {
        let file = SoulStore.load() ?? SoulFile(metadata: .default, body: "")
        name = file.metadata.name
        rawEmoji = file.metadata.emoji
        icon = file.metadata.icon
        style = file.metadata.style
        lang = file.metadata.lang
        bodyText = file.body
        loadedRef.value = file
        saveError = nil
    }

    private func save() {
        do {
            let f = currentFile
            try SoulStore.save(f)
            loadedRef.value = f
            saveError = nil
            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { didJustSave = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) { didJustSave = false }
            }
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Bidirectional Soul sync: push local SOUL.md up and pull the
    /// latest remote SoulV2 down. Mirrors `ProviderInstancesView`'s
    /// Force iCloud Sync entry (which uses the same `bidirectionalSync`
    /// helper). iOS-17 gated because the v2 sync surface is.
    @available(iOS 17.0, *)
    @MainActor
    private func forceSyncSoul() async {
        // 1. Re-mark local SOUL.md dirty (if present) so the upload
        //    side ships our copy.
        _ = await ForceSyncHelper.markSoulDirty()
        // 2. Run a full sendNow + fullFetchAndReconcile cycle so any
        //    peer-newer SoulV2 lands and the merger overwrites local
        //    via SoulStore.applyRemoteContent (LWW by mtime).
        await ForceSyncHelper.bidirectionalSync(recordTypes: ["SoulV2"])
        // 3. Re-read the on-disk file in case the merger just replaced
        //    it with a peer's newer copy — otherwise the form stays
        //    showing the pre-sync values.
        reload()
        showForceSyncDone = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showForceSyncDone = false }
    }

    private func restoreDefault() {
        let parsed = SoulMDParser.parse(SoulStore.defaultContent)
        name = parsed.metadata.name
        rawEmoji = parsed.metadata.emoji
        style = parsed.metadata.style
        lang = parsed.metadata.lang
        bodyText = parsed.body
        save()
    }

    private final class LoadedFileRef: ObservableObject {
        var value: SoulFile = SoulFile(metadata: .default, body: "")
    }
}

private extension Character {
    /// True for characters that are genuinely emoji.
    ///
    /// `isEmoji` alone is not enough: Unicode gives ASCII digits and `#`/`*`
    /// the Emoji property (they are the bases of keycap sequences like 1️⃣), so
    /// a bare "1" would pass. The rule below accepts a scalar only when it
    /// either defaults to emoji presentation, or is part of a multi-scalar
    /// cluster (a keycap, flag or ZWJ sequence), which is what excludes plain
    /// digits and letters while keeping 1️⃣ and 🇯🇵.
    var isEmojiGlyph: Bool {
        guard let first = unicodeScalars.first else { return false }
        if unicodeScalars.count > 1 {
            return unicodeScalars.contains { $0.properties.isEmoji }
        }
        return first.properties.isEmojiPresentation
    }
}

/// [T-soul-custom-icon] Emoji picker for the Soul identity icon: two rows of
/// suggestions plus a free-form field.
///
/// The suggestions are all **Unicode 6.0 (2010)** characters — the original
/// emoji block that every platform has shipped for over a decade. That matters
/// because this value syncs: an icon set on iOS is read by the Android build
/// and rendered with the system font there. Newer additions (🫡 U+1FAE1, 2021;
/// 🩻 2022) render as a blank box on anything that has not updated its font,
/// which would look like data loss rather than a style choice. Skin-toned and
/// ZWJ-sequence emoji are avoided for the same reason.
///
/// Chosen for "an agent's face": expressive enough to read as a persona at
/// 18pt in the chat header, and visually distinct from each other at that size.
private struct SoulEmojiPickerSheet: View {
    @Binding var draft: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let suggestions: [[String]] = [
        ["✨", "🤖", "🐱", "🦊", "🐧", "🦉", "🌟", "⚡"],
        ["🧠", "💡", "🔮", "🚀", "🌊", "🍀", "🎯", "🐳"],
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Live preview at the size the chat header actually uses, so
                // the user judges the glyph at its real scale rather than at
                // whatever the field happens to render.
                // Same circular treatment as the settings card, so the preview
                // shows what the icon will actually look like in place.
                SoulIconView(icon: draft, size: SoulIconImage.renderPoints)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(CodyColors.bgListIcon))
                    .padding(.top, 8)

                ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { emoji in
                            Button {
                                // Tap fills the field AND becomes the value —
                                // "点击和自动填入".
                                draft = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 28))
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Circle().fill(draft == emoji
                                                      ? CodyColors.textAccent.opacity(0.18)
                                                      : CodyColors.interactiveSecondaryBg)
                                    )
                            }
                            .buttonStyle(CodyPressableButtonStyle())
                            .accessibilityAddTraits(draft == emoji ? .isSelected : [])
                        }
                    }
                }

                TextField("✨", text: $draft)
                    .font(.system(size: 28))
                    .multilineTextAlignment(.center)
                    .frame(height: 52)
                    .background(CodyColors.interactiveSecondaryBg, in: RoundedRectangle(cornerRadius: CodyRadius.control))
                    // Every keystroke is normalized to a single emoji: typing
                    // a second one REPLACES the first, and non-emoji input is
                    // dropped outright rather than rejected later with an
                    // error the user has to read.
                    .onChange(of: draft) { newValue in
                        let cleaned = Self.normalize(newValue, previous: draft)
                        if cleaned != newValue { draft = cleaned }
                    }

                Text(AppLocalized("Tap a suggestion or type one emoji. These render the same on iOS and Android."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .navigationTitle(AppLocalized("Choose Emoji"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalized("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Set")) {
                        onPick(draft)
                        dismiss()
                    }
                    .disabled(draft.isEmpty)
                }
            }
        }
        .presentationDetents([.height(380)])
    }

    /// Keep at most one emoji, preferring whatever the user just added.
    ///
    /// Works on `Character` (grapheme clusters) so a flag or ZWJ sequence —
    /// several scalars rendering as one glyph — survives as a single unit
    /// instead of being sliced apart.
    static func normalize(_ input: String, previous: String) -> String {
        let emoji = input.filter(\.isEmojiGlyph)
        guard let last = emoji.last else { return "" }
        // Taking the LAST emoji is what makes a second keystroke replace the
        // first rather than being ignored.
        return String(last)
    }
}

/// [T-soul-custom-icon] The icon picker's presentation chain, lifted out of
/// `SoulSettingsView.body`.
///
/// Not a style choice: inlining these four presentation modifiers pushed the
/// `body` expression past what the type-checker will solve ("unable to
/// type-check this expression in reasonable time"). A ViewModifier gives the
/// solver a fresh, small expression to work on.
private struct SoulIconEditing: ViewModifier {
    @Binding var icon: String
    @Binding var showEmojiPrompt: Bool
    @Binding var emojiDraft: String
    @Binding var showPhotoPicker: Bool
    @Binding var photoItem: PhotosPickerItem?
    @Binding var iconError: String?

    func body(content: Content) -> some View {
        content
            // A sheet, not an alert: an alert body only takes text fields and
            // buttons, so the suggestion grid could not live in one.
            .sheet(isPresented: $showEmojiPrompt) {
                SoulEmojiPickerSheet(draft: $emojiDraft) { chosen in
                    icon = chosen
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem,
                          matching: .images, photoLibrary: .shared())
            // Single-parameter form: the two-parameter `onChange` is iOS 17+,
            // and this target still deploys lower.
            .onChange(of: photoItem) { newItem in
                guard let newItem else { return }
                Task { await applyPickedImage(newItem) }
            }
            .alert(AppLocalized("Can't use that image"),
                   isPresented: Binding(get: { iconError != nil },
                                        set: { if !$0 { iconError = nil } })) {
                Button(AppLocalized("OK"), role: .cancel) { iconError = nil }
            } message: {
                Text(iconError ?? "")
            }
    }

    /// Accept exactly one emoji.
    ///
    /// Counting `Character`s (grapheme clusters), not scalars, so a flag or a
    /// skin-toned/ZWJ emoji — several scalars rendering as one glyph — counts
    /// as one. Empty input clears back to the default rather than storing a
    /// blank.
    private func applyEmojiDraft() {
        let trimmed = emojiDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { icon = ""; return }
        guard trimmed.count == 1 else {
            iconError = AppLocalized("Please enter exactly one emoji.")
            return
        }
        icon = trimmed
    }

    /// Load, validate and normalize a picked photo into the stored form.
    private func applyPickedImage(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run { iconError = AppLocalized("That image couldn't be read.") }
            return
        }
        // [T-soul-icon-opaque-rounded] Opaque images are accepted now — the
        // transparency requirement was a presentation concern and moved to
        // `SoulIconView`, which clips every image to a rounded rectangle. Only
        // an undecodable image is refused here, so this path and the
        // `cody-config` path apply exactly the same rule.
        switch SoulIconImage.encode(image) {
        case .success(let uri):
            await MainActor.run { icon = uri }
        case .failure:
            await MainActor.run {
                iconError = AppLocalized("That image couldn't be read.")
            }
        }
    }
}
