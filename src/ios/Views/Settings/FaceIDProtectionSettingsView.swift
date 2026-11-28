//
//  FaceIDProtectionSettingsView.swift
//  CodyApp
//
//  Settings entry for per-session biometric protection. Surfaces the
//  master toggle, an idle-timeout picker, and (when relevant) a count of
//  currently-locked sessions with a "clear all" affordance.
//
//  Hidden in the parent settings list when the device lacks biometric
//  capability — see `BiometricAuth.isAvailable`.
//

import SwiftUI

struct FaceIDProtectionSettingsView: View {
    @ObservedObject private var store = SessionLockStore.shared
    @AppStorage(SessionLockDefaultsKey.enabled) private var enabled: Bool = false
    @AppStorage(SessionLockDefaultsKey.idleSeconds) private var idleSeconds: Int = 300
    @AppStorage(SessionLockDefaultsKey.appLockEnabled) private var appLockEnabled: Bool = false
    @AppStorage(SessionLockDefaultsKey.appLockIdleSeconds) private var appLockIdleSeconds: Int = -1

    var body: some View {
        CodySettingsScrollPage {
            // MARK: - App Lock
            CodySettingsNovaSection(footer: "When enabled, \(BiometricAuth.biometryDisplayName) (or device passcode) is required every time you open the app.") {
                Toggle(isOn: $appLockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock App")
                        Text("Require \(BiometricAuth.biometryDisplayName) to cody.")
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
                .onChange(of: appLockEnabled) { newValue in
                    guard newValue else {
                        store.appLockEnabled = false
                        return
                    }
                    Task { @MainActor in
                        let reason = AppLocalized("Enable \(BiometricAuth.biometryDisplayName) app lock")
                        let ok = await BiometricAuth.authenticate(reason: reason)
                        if ok {
                            store.appLockEnabled = true
                            store.noteAppUnlock()
                        } else {
                            appLockEnabled = false
                        }
                    }
                }
                .settingsNovaControlRow()
            }

            if appLockEnabled {
                CodySettingsNovaSection("App Lock Timeout", footer: "How long after leaving the app before the lock re-engages.") {
                    Picker(AppLocalized("Require unlock"), selection: $appLockIdleSeconds) {
                        ForEach(SessionLockIdleOption.allOptions) { opt in
                            Text(opt.labelKey).tag(opt.seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: appLockIdleSeconds) { newValue in
                        store.appLockIdleSeconds = newValue
                    }
                    .settingsNovaControlRow()
                }
            }

            // MARK: - Per-Session Lock
            CodySettingsNovaSection(footer: "When enabled, locked sessions require \(BiometricAuth.biometryDisplayName) (or device passcode) before their contents are revealed.") {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock Sessions")
                        Text("Long-press a session in the list to lock it.")
                            .font(CodyTypography.bodySmall)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }
                .onChange(of: enabled) { newValue in
                    guard newValue else { return }
                    Task { @MainActor in
                        let reason = AppLocalized("Enable \(BiometricAuth.biometryDisplayName) protection for chat sessions")
                        let ok = await BiometricAuth.authenticate(reason: reason)
                        if !ok {
                            enabled = false
                        }
                    }
                }
                .settingsNovaControlRow()
            }

            if enabled {
                CodySettingsNovaSection("Session Lock Timeout", footer: "After leaving an unlocked session, the lock re-engages once the idle window elapses.") {
                    Picker(AppLocalized("Re-lock after idle"), selection: $idleSeconds) {
                        ForEach(SessionLockIdleOption.allOptions) { opt in
                            Text(opt.labelKey).tag(opt.seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    .settingsNovaControlRow()
                }

                CodySettingsNovaSection {
                    HStack {
                        Text("Locked sessions")
                        Spacer()
                        Text("\(store.lockedSessionIds.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .settingsNovaControlRow()
                    if !store.lockedSessionIds.isEmpty {
                        CodySettingsNovaDivider(leadingInset: CodySpacing.lg)
                        Button(role: .destructive) {
                            Task { @MainActor in
                                let reason = AppLocalized("Remove all session locks")
                                let ok = await BiometricAuth.authenticate(reason: reason)
                                if ok {
                                    for sid in store.lockedSessionIds {
                                        store.unlockPermanently(sid)
                                    }
                                }
                            }
                        } label: {
                            SettingsIconLabel(title: Text("Remove All Locks"), systemImage: "lock.open", tint: .red)
                                .foregroundStyle(CodyColors.statusErrorText)
                                .settingsNovaControlRow()
                        }
                        .buttonStyle(CodyPressableButtonStyle())
                    }
                }
            }
        }
        .navigationTitle("\(BiometricAuth.biometryDisplayName) Protection")
        .navigationBarTitleDisplayMode(.inline)
    }
}
