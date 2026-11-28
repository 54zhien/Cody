import SwiftUI
import UIKit

struct AboutView: View {
    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }()

    /// When this binary was built, from the executable's modification date.
    ///
    /// Exists because the version string alone cannot answer "is the fix I
    /// just shipped actually running on that device?" — CFBundleVersion is
    /// static across rebuilds, so an OTA install that silently didn't replace
    /// the app looks identical to one that did. That ambiguity has cost real
    /// debugging time on the test devices. Same source as the debug server's
    /// `buildDate`, but visible in Release too, where no debug server exists.
    /// [T-env-diagnostic-line] One line naming the RUNTIME environment, for
    /// bug reports.
    ///
    /// A macOS 27 rendering report cost a full round trip because nothing in
    /// the app said which environment it was: "Designed for iPad" (an
    /// unmodified iOS binary on Apple Silicon) and Mac Catalyst (UIKit bridged
    /// onto AppKit) look identical in a screenshot but share almost no
    /// rendering path, and the SDK release notes that explain a symptom apply
    /// to one and not the other. Guessing wrong sends the whole diagnosis down
    /// the wrong track.
    ///
    /// `isiOSAppOnMac` is the authoritative discriminator and is what
    /// distinguishes the two; `targetEnvironment(macCatalyst)` is resolved at
    /// COMPILE time, so it reports how this binary was built rather than where
    /// it is running — both are printed because the pair is what identifies
    /// the mode unambiguously.
    private let environmentLine: String = {
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
        let idiom: String = switch UIDevice.current.userInterfaceIdiom {
        case .phone: "phone"
        case .pad: "pad"
        case .mac: "mac"
        case .tv: "tv"
        case .carPlay: "carPlay"
        case .vision: "vision"
        default: "unspecified"
        }
        #if targetEnvironment(macCatalyst)
        let built = "catalyst"
        #else
        let built = "ios"
        #endif
        let onMac = ProcessInfo.processInfo.isiOSAppOnMac
        // "iOSAppOnMac" is Designed for iPad; "catalyst" built + not
        // isiOSAppOnMac is a true Catalyst run; otherwise a real device.
        let mode = onMac ? "iOSAppOnMac" : (built == "catalyst" ? "catalyst" : "device")
        return "\(mode) · \(idiom) · OS \(os) · built:\(built)"
    }()

    private let buildDate: String = {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mod = attrs[.modificationDate] as? Date
        else { return "unknown" }
        let fmt = DateFormatter()
        // Local time, seconds included: this gets compared by eye against the
        // timestamp of a build that just finished.
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: mod)
    }()

    var body: some View {
        CodySettingsScrollPage {
            brandingHeader
            CodySettingsNovaSection {
                detailsRow("Version", value: appVersion)
                CodySettingsNovaDivider(leadingInset: 18)
                detailsRow("Built", value: buildDate)
                CodySettingsNovaDivider(leadingInset: 18)
                detailsRow("Environment", value: environmentLine)
            }
            CodySettingsNovaSection("Licenses") {
                externalLink("Cody License", url: "https://github.com/54zhien/Cody/blob/main/LICENSE")
                CodySettingsNovaDivider(leadingInset: 18)
                externalLink("Third-Party Licenses", url: "https://github.com/54zhien/Cody/blob/main/THIRD_PARTY_LICENSES.md")
            }
            CodySettingsNovaSection("Links") {
                externalLink("GitHub Repository", url: "https://github.com/54zhien/Cody")
                CodySettingsNovaDivider(leadingInset: 18)
                externalLink("Report an Issue", url: "https://github.com/54zhien/Cody/issues")
                CodySettingsNovaDivider(leadingInset: 18)
                externalLink("Privacy Policy", url: "https://54zhien.github.io/Cody/privacy-policy.html")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var brandingHeader: some View {
        VStack(spacing: CodySpacing.sm) {
            if let icon = UIImage(named: "AppIcon60x60") ?? UIImage(named: "AppIcon") {
                let shape = RoundedRectangle(cornerRadius: CodyRadius.surface, style: .continuous)
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px) }
                    .accessibilityHidden(true)
            }
            Text("Cody")
                .font(CodyTypography.headlineSmall)
                .foregroundStyle(CodyColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Cody is Your Fully Local, Fully Private On-Device Agent.")
                .font(CodyTypography.bodyMedium)
                .foregroundStyle(CodyColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CodySpacing.lg)
        .multilineTextAlignment(.center)
    }

    private func detailsRow(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: CodySpacing.xxs) {
            Text(title)
                .font(CodyTypography.bodyLarge)
                .foregroundStyle(CodyColors.textPrimary)
            Text(verbatim: value)
                .font(CodyTypography.bodySmall)
                .foregroundStyle(CodyColors.textSecondary)
                .textSelection(.enabled)
        }
        .settingsNovaControlRow(minHeight: CodyMetrics.Settings.navRowMinHeight)
    }

    private func externalLink(_ title: LocalizedStringKey, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            CodySettingsNovaRowContent(title: title, subtitle: nil, systemImage: nil, tint: nil, showsDisclosure: false) {
                CodyIconView(.externalLink, size: 17)
                    .foregroundStyle(CodyColors.iconDisclosure)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}
