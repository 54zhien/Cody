//
//  AIChatView+NavigationTitle.swift
//  Cody - chat page (AIChatView)
//
//  AIChatView, navigation title: the principal toolbar content hosted by
//  ChatToolbarHost and its equatable keys, the title / model selector view,
//  speed tier and fast-mode availability, the thinking-level badge, and the
//  session title snapshot used by the title pill.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import AVFoundation
import AVKit
import Combine
import GameController
import PhotosUI
import QuickLook
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

extension AIChatView {
    // MARK: - Navigation Title + Model Selector

    /// [T-ios-navbar-toolbar-host] Principal toolbar content, extracted from
    /// the old inline ToolbarItem so ChatToolbarHost can render it. Layout
    /// preserved verbatim:
    /// [T-navbar-title-centering] iOS 18 and below let the principal toolbar
    /// item shrink to its content width and anchor it left-of-center; iOS 19+
    /// centers natively — wrap in an infinite-width HStack with bookend
    /// Spacers on legacy iOS, and cap the width to (screen − ~140pt chrome)
    /// so long titles truncate instead of pushing through the trailing menu.
    @ViewBuilder
    var chatNavPrincipalContent: some View {
        // Cap the title width to (screen − chrome) on ALL versions.
        //
        // [NavTitleGestureTruncation 2026-07-24] iOS 19+ previously left the
        // titleView unconstrained, letting the system principal toolbar decide
        // the truncation width from whatever space the left/right bar items
        // leave. During an INTERACTIVE pop (edge-swipe), the system snapshots
        // the nav bar and interpolates bar-item positions; at some drag/cancel
        // frames the principal's available width widens, so lineLimit(1) stops
        // truncating and a long title momentarily "un-truncates" to its full
        // form — a jarring jump when the user cancels the swipe. Pinning an
        // explicit, version-stable cap makes the truncation point identical in
        // the steady state and every transition frame, so the title never
        // pops to full. Does not affect normal-length titles (they're under
        // the cap). This is a MITIGATION of the system snapshot behavior, not
        // a fix of it: the top-crop of the snapshot itself is UIKit-level and
        // out of SwiftUI's reach.
        let cap = max(120, UIScreen.main.bounds.width - (isNovaHostedChat ? 196 : 140))
        if #available(iOS 19, *) {
            titleView
                .frame(maxWidth: cap)
        } else {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                titleView
                    .frame(maxWidth: cap)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// [T-ios-navbar-toolbar-host] Everything the toolbar DISPLAYS (principal
    /// title + trailing menu), snapshotted as one Equatable key gating the
    /// whole ToolbarContent rebuild.
    var chatToolbarKey: ChatToolbarKey {
        ChatToolbarKey(
            navTitle: navTitleKey,
            messagesEmpty: vm.messages.isEmpty,
            hasSession: vm.sessionId != nil,
            isForcePulling: isForcePulling,
            iCloudSyncEnabled: iCloudSyncEnabled,
            memoryEnabled: vm.memoryEnabled,
            speakEnabled: cached.vm.speakEnabled,
            showEnhancedCacheToggle: cached.vm.showEnhancedCacheToggle,
            enhancedCacheEnabled: cached.vm.enhancedCacheEnabled,
            showFastModeToggle: activeModelSupportsFastMode,
            speedTier: displayedSpeedTier,
            showUltrafast: activeModelSupportsUltrafast,
            showsNovaDrawer: isNovaHostedChat && openNovaDrawer != nil,
            showsNovaNewChat: isNovaHostedChat && !vm.messages.isEmpty,
            keepAwakeEnabled: keepAwakeThisChat,
            screenSaverNowEnabled: screenSaverNowThisChat
        )
    }

    /// [T-codex-fast-mode] True when the session's active model can use Fast
    /// Mode. Broadened from Codex-OAuth-only to: ANY
    /// Responses-API provider + a gpt-family model. Concretely the request
    /// must travel the Responses API path — providerType .openAIResponses
    /// (any credential/base, e.g. sub2api relays, which pass service_tier
    /// through), or the genuine Codex OAuth route (.openAI + OAuth + no
    /// custom base) — and the model id must contain "gpt" (mirrors the
    /// official fast catalog: gpt-5.6-sol/terra/luna, gpt-5.5, gpt-5.4).
    /// [T-codex-speed-tier] The chosen tier (tier key, else the legacy Bool).
    private var storedSpeedTier: SpeedTier {
        SpeedTier(rawValue: speedTierRaw) ?? (codexFastModeEnabled ? .fast : .standard)
    }

    /// [T-codex-speed-tier] Ultrafast is offered on top of Fast only for a
    /// whitelisted model on the Responses / Codex OAuth route — never xAI,
    /// whose Priority Processing has no Ultrafast. The whitelist and why it is
    /// one: SpeedTierSettings.supportsUltrafast.
    var activeModelSupportsUltrafast: Bool {
        guard activeModelSupportsFastMode else { return false }
        let display = SessionModelDisplay(store: configStore, draftGroupId: vm.initialGroupId)
        guard let (instance, modelId) = display.resolvedInstanceAndModel(for: vm.sessionId),
              instance.providerType != .xAI else { return false }
        return SpeedTierSettings.supportsUltrafast(modelId: modelId)
    }

    /// [T-codex-speed-tier] The tier the menu and the badge show — the one the
    /// request will use: Ultrafast chosen but not offered for this model reads
    /// (and is sent) as Fast.
    var displayedSpeedTier: SpeedTier {
        guard activeModelSupportsFastMode else { return .standard }
        let stored = storedSpeedTier
        if stored == .ultrafast, !activeModelSupportsUltrafast { return .fast }
        return stored
    }

    var activeModelSupportsFastMode: Bool {
        let display = SessionModelDisplay(store: configStore, draftGroupId: vm.initialGroupId)
        guard let (instance, modelId) = display.resolvedInstanceAndModel(for: vm.sessionId) else { return false }
        // [T-xai-priority-processing] xAI Priority Processing is the same
        // user-facing feature (pay more, go faster) reached through the same
        // "…" menu switch, so xAI models offer it too. Checked BEFORE the
        // gpt-family guard below: xAI ships grok-*, so requiring "gpt" in the
        // model id would silently never show the switch. Provider-type match
        // rather than a URL sniff, mirroring how the OpenAI branches identify
        // their route; the request-side `isXAI` host check in OpenAIProvider
        // stays as the second gate.
        if instance.providerType == .xAI { return true }
        guard modelId.lowercased().contains("gpt") else { return false }
        if instance.providerType == .openAIResponses { return true }
        return instance.providerType == .openAI
            && instance.credentialType == .oauth
            && (instance.customBaseURL?.isEmpty ?? true)
    }

    /// [T-ios-navbar-principal-streaming-stability] Snapshot of everything
    /// titleView displays — must stay in lockstep with titleView's reads
    /// (see NavTitleKey doc). Cheap to compute per body pass.
    private var navTitleKey: NavTitleKey {
        #if DEBUG
        NavbarEvalStats.toolbarPass += 1
        #endif
        let display = SessionModelDisplay(store: configStore, draftGroupId: vm.initialGroupId)
        let resolved = display.resolvedDetail(for: vm.sessionId)
        let selectionName = display.displayName(for: vm.sessionId)
        let modelName = resolved?.modelName ?? selectionName
        let hasBinding = vm.sessionId.flatMap { configStore.binding(for: $0) } != nil
        let hasProviders = !configStore.instances.isEmpty
        let currentEntry = vm.resolveCurrentEntry()
        let sessionTitle: String? = (titlePillSession?.title?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
        return NavTitleKey(
            sessionTitle: sessionTitle,
            canEditTitle: titlePillSession != nil,
            soulName: soulName,
            modelName: modelName == AppLocalized("No model selected") ? AppLocalized("Select Model") : modelName,
            isGroupBound: display.isGroupBound(for: vm.sessionId),
            speedBadge: displayedSpeedTier,
            resolvedText: resolved.map { "\($0.providerLabel) · \($0.modelName)" },
            hasBinding: hasBinding,
            hasProviders: hasProviders,
            showThinkingBadge: !vm.availableThinkingLevels.isEmpty
                && (vm.currentThinkingLevel.isEnabled || vm.currentModelSupportsReasoning),
            thinkingLevelName: vm.currentThinkingLevel.displayName,
            fallbackTrigger: vm.fallbackTrigger,
            fallbackPulse: fallbackPulseOpacity,
            titleLocked: titleIsVisuallyLocked,
            modelInstanceId: currentEntry?.providerInstanceId,
            modelId: currentEntry?.baseModel.id
        )
    }

    private var titleView: some View {
        let key = navTitleKey
        let reduceMotion = self.reduceMotion
        let displayTitle = key.sessionTitle ?? key.soulName
        return Button {
            dismissChatKeyboard()
            if key.canEditTitle {
                titlePillEditSession = titlePillSession
            }
        } label: {
            Text(displayTitle)
                .font(CodyTypography.titleSmall)
                .foregroundStyle(CodyColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .modifier(NovaModelPillSurface(fallbackPulseOpacity: fallbackPulseOpacity))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(displayTitle))
        .accessibilityHint(key.canEditTitle ? Text("Edit session title") : Text(""))
        .onChange(of: vm.fallbackTrigger) { _ in
            fallbackPulseOpacity = 0
            for step in 0..<6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.35) {
                    withAnimation(CodyMotion.resolved(.easeInOut(duration: 0.35), reduceMotion: reduceMotion)) {
                        fallbackPulseOpacity = step.isMultiple(of: 2) ? 1 : 0
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            let name = SoulStore.cachedMetadata.name
            soulName = name.isEmpty ? "Cody" : name
        }
        .modifier(NavTitleFrameModifier())
        // The system toolbar has a fixed vertical band.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .blur(radius: titleIsVisuallyLocked ? 8 : 0)
        .allowsHitTesting(!titleIsVisuallyLocked)
        .accessibilityHidden(titleIsVisuallyLocked)
        .animation(CodyMotion.resolved(.easeInOut(duration: 0.15), reduceMotion: reduceMotion),
                   value: titleIsVisuallyLocked)
    }

    private var thinkingLevelBadge: some View {
        let level = vm.currentThinkingLevel
        return Button {
            dismissChatKeyboard()
            showThinkingLevelSheet = true
        } label: {
            HStack(spacing: CodySpacing.xxs) {
                Image("ThinkingIcon")
                    .resizable()
                    .frame(width: 8, height: 8)
                    .opacity(level.isEnabled ? 1.0 : 0.4)
                    .accessibilityHidden(true)
                Text(level.displayName)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(CodyColors.textSecondary)
            .padding(.horizontal, CodySpacing.xs)
            .padding(.vertical, CodySpacing.xxs)
            .background(Capsule().fill(CodyColors.bgTertiary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Thinking level"))
        .accessibilityValue(Text(level.displayName))
        .sheet(isPresented: $showThinkingLevelSheet) {
            ThinkingLevelSheetView(
                currentLevel: level,
                availableLevels: vm.availableThinkingLevels,
                onSelect: { newLevel in
                    vm.setThinkingLevel(newLevel)
                    showThinkingLevelSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }

    /// True when the current session's navbar title must render blurred —
    /// observed via `@ObservedObject lockStore` so toggles to the lock
    /// state push a re-render of the toolbar synchronously with the gate.
    var titleIsVisuallyLocked: Bool {
        guard let sid = vm.sessionId, !sid.isEmpty else { return false }
        return lockStore.isVisuallyLocked(sid)
    }

    // MARK: - Session Title Snapshot

    func refreshTitlePillSession() {
        guard let sid = vm.sessionId else {
            titlePillSession = nil
            return
        }
        // ChatStore is an actor — must await off the main actor. Bouncing
        // back to the main actor before mutating @State avoids the strlen /
        // SQLite data race that crashed when called synchronously from the
        // view body (concurrent with sync engine writes).
        Task {
            let next = await ChatStore.shared.getSession(sid)
            await MainActor.run {
                guard sid == vm.sessionId else { return }
                if next?.id != titlePillSession?.id
                    || next?.title != titlePillSession?.title
                    || next?.category != titlePillSession?.category {
                    // Direct replace — animating the toolbar title makes the
                    // old "Cody" string slide before the real title swaps
                    // in, which looks broken. SwiftUI's default crossfade
                    // for non-animated text changes is what we want.
                    titlePillSession = next
                }
            }
        }
    }
}

// Quota notifications update this control without rebuilding the toolbar.
private struct NovaModelPickerButton: View {
    let key: NavTitleKey
    let onSelect: () -> Void
    let onRename: (() -> Void)?
    @ObservedObject private var quota = QuotaStore.shared

    private var isAuthed: Bool { key.hasBinding || key.hasProviders }

    private var quotaLow: Bool {
        isAuthed && ModelQuotaStatusDot.isLow(instanceId: key.modelInstanceId, modelId: key.modelId, quota: quota)
    }

    var body: some View {
        let displayedSpeedTier = key.speedBadge
        Button {
            onSelect()
        } label: {
            HStack(spacing: CodySpacing.xsPlus) {
                Text(key.modelName)
                    .font(CodyTypography.titleSmall)
                    .foregroundStyle(CodyColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                if let symbol = displayedSpeedTier.badgeSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CodyColors.iconSecondary)
                        .accessibilityLabel(Text(verbatim: displayedSpeedTier.title))
                }
                ModelQuotaStatusDot(isAuthed: isAuthed,
                                    instanceId: key.modelInstanceId,
                                    modelId: key.modelId)
                    .scaleEffect(0.83)
                CodyIconView(.chevronDown, size: 13)
                    .foregroundStyle(CodyColors.iconTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Model", comment: "VoiceOver label for the model picker button"))
        .accessibilityValue(modelPickerAccessibilityValue)
        .accessibilityHint(Text("Opens the model picker", comment: "VoiceOver hint for the model picker button"))
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if let onRename {
                Button("Edit session title", action: onRename)
            }
        }
    }

    private var modelPickerAccessibilityValue: Text {
        let modelName = key.modelName
        let model: String
        if key.isGroupBound {
            model = isAuthed
                ? AppLocalized("\(modelName), group, signed in", comment: "VoiceOver value: model picker, group-bound, authenticated")
                : AppLocalized("\(modelName), group, not signed in", comment: "VoiceOver value: model picker, group-bound, not authenticated")
        } else {
            model = isAuthed
                ? AppLocalized("\(modelName), signed in", comment: "VoiceOver value: model picker, authenticated")
                : AppLocalized("\(modelName), not signed in", comment: "VoiceOver value: model picker, not authenticated")
        }
        let speed = key.speedBadge == .standard ? "" : ", \(key.speedBadge.title)"
        return Text(verbatim: model + speed)
            + Text(quotaLow ? AppLocalized(", quota low", comment: "VoiceOver: appended to the model value when the model's quota or balance is low") : "")
    }
}

/// Nova sheet expanded directly from long-pressing the chat composer:
/// combines a hairline-capsule Thinking Intensity pill selector with the full Model Picker.
struct NovaComposerModelSheet: View {
    @ObservedObject var vm: AIChatViewModel
    let sessionId: String?
    let ensureSessionId: () async -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsThinkingSection: Bool {
        !vm.availableThinkingLevels.isEmpty
            && (vm.currentThinkingLevel.isEnabled || vm.currentModelSupportsReasoning)
    }

    var body: some View {
        NavigationStack {
            SessionModelPicker(sessionId: sessionId, ensureSessionId: ensureSessionId)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showsThinkingSection {
                        thinkingIntensityBar
                    }
                }
        }
        .background(CodyColors.bgCanvas.ignoresSafeArea())
    }

    private var thinkingIntensityBar: some View {
        let levels: [ThinkingLevel] = [.off] + vm.availableThinkingLevels
        let current = vm.currentThinkingLevel
        return VStack(alignment: .leading, spacing: CodySpacing.sm) {
            HStack(spacing: CodySpacing.xsPlus) {
                Image("ThinkingIcon")
                    .resizable()
                    .frame(width: 15, height: 15)
                    .opacity(current.isEnabled ? 1.0 : 0.45)
                    .accessibilityHidden(true)
                Text("Thinking Intensity")
                    .font(CodyTypography.labelLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                Spacer(minLength: CodySpacing.sm)
                Text(current.displayName)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CodySpacing.xsPlus) {
                    ForEach(levels, id: \.self) { level in
                        let isSelected = (level == .off) ? !current.isEnabled : (current == level)
                        Button {
                            guard !isSelected else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion)) {
                                vm.setThinkingLevel(level)
                            }
                        } label: {
                            Text(level.displayName)
                                .font(CodyTypography.labelMedium)
                                .foregroundStyle(isSelected ? CodyColors.interactivePrimaryLabel : CodyColors.textPrimary)
                                .padding(.horizontal, CodySpacing.md)
                                .frame(minHeight: 34)
                                .background {
                                    Capsule()
                                        .fill(isSelected ? CodyColors.interactivePrimaryBg : CodySettingsHairline.cardFill)
                                }
                                .overlay {
                                    if !isSelected {
                                        Capsule()
                                            .strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal, CodySpacing.mdPlus)
        .padding(.vertical, CodySpacing.md)
        .codySettingsCapsulePill()
        .padding(.horizontal, CodySpacing.lg)
        .padding(.top, CodySpacing.xs)
        .padding(.bottom, CodySpacing.sm)
        .background(CodyColors.bgCanvas)
    }
}

/// Marks the chat composer capsule as the iOS 18+ zoom transition source for `NovaComposerModelSheet`.
struct ComposerZoomSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Applies the iOS 18+ zoom transition (and rounded sheet radius on iOS 16.4+) so
/// `NovaComposerModelSheet` expands directly out of the composer.
struct ComposerZoomDestinationModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .navigationTransition(.zoom(sourceID: id, in: namespace))
                .presentationCornerRadius(32)
        } else if #available(iOS 16.4, *) {
            content
                .presentationCornerRadius(32)
        } else {
            content
        }
    }
}

/// Standard iOS 26 interactive Liquid Glass capsule surface for the chat header title capsule,
/// with clean translucent fallback on iOS 16–25 and Reduce Transparency.
private struct NovaModelPillSurface: ViewModifier {
    let fallbackPulseOpacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay {
                    Capsule()
                        .fill(Color.red.opacity(0.35 * fallbackPulseOpacity))
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        } else {
            content
                .background {
                    Capsule()
                        .fill(CodyColors.interactiveSecondaryBg.opacity(0.82))
                        .overlay { Capsule().fill(Color.red.opacity(0.35 * fallbackPulseOpacity)) }
                }
                .overlay {
                    Capsule().strokeBorder(CodyColors.borderLight, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
    }
}
