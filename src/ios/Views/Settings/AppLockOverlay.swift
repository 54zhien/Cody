import SwiftUI

struct AppLockOverlay: View {
    @ObservedObject private var store = SessionLockStore.shared
    @State private var isAuthenticating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var iconSize = CodySpacing.s48

    var body: some View {
        if store.appIsLocked {
            ZStack {
                CodyColors.bgCanvas
                    .ignoresSafeArea()

                VStack(spacing: CodySpacing.xxl) {
                    Image(systemName: BiometricAuth.biometryIconName)
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(CodyColors.iconPrimary)
                        .accessibilityHidden(true)

                    Text("Cody is Locked")
                        .font(CodyTypography.headlineSmall)
                        .foregroundStyle(CodyColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text("Tap to unlock with \(BiometricAuth.biometryDisplayName)")
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textSecondary)

                    Button {
                        authenticate()
                    } label: {
                        Text("Unlock")
                            .font(CodyTypography.titleMedium)
                            .padding(.horizontal, CodySpacing.lg)
                    }
                    .buttonStyle(CodyPrimaryCapsuleButtonStyle())
                    .disabled(isAuthenticating)
                }
                .padding(CodySpacing.xxl)
                .multilineTextAlignment(.center)
            }
            .transition(reduceMotion ? .identity : .opacity)
            .onAppear {
                authenticate()
            }
        } else if store.showPrivacyScreen {
            CodyColors.bgCanvas
                .ignoresSafeArea()
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task { @MainActor in
            let reason = AppLocalized("Unlock Cody")
            let ok = await BiometricAuth.authenticate(reason: reason)
            if ok {
                withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                    store.noteAppUnlock()
                }
            }
            isAuthenticating = false
        }
    }
}
