import SwiftUI
import UIKit

/// Crisp visible hairline stroke and pure surface fills matching the outlined-capsule Settings design:
/// - Light mode: pure white canvas (#FFFFFF) + pure white capsule surface (#FFFFFF) + 1pt crisp hairline stroke
/// - Dark mode: pure black canvas (#000000) + elevated dark capsule surface (#181818) + 1pt crisp hairline stroke
enum CodySettingsHairline {
    static let strokeColor = Color(
        uiColor: CodyUIColors.dynamic(
            light: 0x000000,
            lightAlpha: 0.10,
            dark: 0xFFFFFF,
            darkAlpha: 0.14
        )
    )

    static let dividerColor = Color(
        uiColor: CodyUIColors.dynamic(
            light: 0x000000,
            lightAlpha: 0.08,
            dark: 0xFFFFFF,
            darkAlpha: 0.10
        )
    )

    static let cardFill = Color(
        uiColor: CodyUIColors.dynamic(
            light: 0xFFFFFF,
            dark: 0x181818
        )
    )

    static let capsuleRadius: CGFloat = 28
}

/// Full-page ScrollView host for Nova Settings screens over a clean pure canvas (`bgCanvas`),
/// letting hairline-outlined 28pt capsule cards stand out cleanly with zero default SwiftUI `List` chrome.
struct CodySettingsScrollPage<Content: View>: View {
    var bottomInset: CGFloat = CodySpacing.xxxl
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(.horizontal, CodySpacing.lg)
            .padding(.top, CodySpacing.md)
            .padding(.bottom, bottomInset)
        }
        .background(CodyColors.bgCanvas.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }
}

/// Outlined 28pt capsule card section (single-row = true full capsule pill; multi-row = capsule-ended outlined group).
struct CodySettingsNovaSection<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey? = nil,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(CodyTypography.bodyMedium.weight(.medium))
                    .foregroundStyle(CodyColors.textSecondary)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }

            let shape = RoundedRectangle(cornerRadius: CodySettingsHairline.capsuleRadius, style: .continuous)
            VStack(spacing: 0) {
                content()
            }
            .background(shape.fill(CodySettingsHairline.cardFill))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }

            if let footer {
                Text(footer)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.top, CodySpacing.sm)
            }
        }
    }
}

/// Standalone capsule-pill stack for individual pill options separated by 12pt spacing.
struct CodySettingsCapsuleGroup<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey? = nil,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(CodyTypography.bodyMedium.weight(.medium))
                    .foregroundStyle(CodyColors.textSecondary)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 12) {
                content()
            }

            if let footer {
                Text(footer)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.top, CodySpacing.sm)
            }
        }
    }
}

/// Wraps any single settings row as an individual 28pt capsule pill with a crisp 1pt hairline border.
struct CodySettingsCapsulePillModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodySettingsHairline.capsuleRadius, style: .continuous)
        content
            .background(shape.fill(CodySettingsHairline.cardFill))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

extension View {
    /// Renders a standalone settings row as a 28pt capsule pill with a crisp 1pt hairline stroke.
    func codySettingsCapsulePill() -> some View {
        modifier(CodySettingsCapsulePillModifier())
    }
}

/// Delicate 0.5pt hairline divider inside a multi-row outlined capsule section.
/// Pass `leadingInset: 54` when rows have leading monochrome icons, or `18` when rows are text-only.
struct CodySettingsNovaDivider: View {
    var leadingInset: CGFloat = 54

    var body: some View {
        Rectangle()
            .fill(CodySettingsHairline.dividerColor)
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

/// Outlined-capsule Settings navigation row (56pt single-line, 70pt with subtitle).
/// Uses clean monochrome line icons (no colored square/circle background boxes) and a subtle disclosure chevron.
struct CodySettingsNovaNavRow<Destination: View, Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String?
    let tint: CodyCategoryTint?
    let showsDisclosure: Bool
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: CodyCategoryTint? = nil,
        showsDisclosure: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.showsDisclosure = showsDisclosure
        self.trailing = trailing
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination) {
            CodySettingsNovaRowContent(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint,
                showsDisclosure: showsDisclosure,
                trailing: trailing
            )
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}

extension CodySettingsNovaNavRow where Trailing == EmptyView {
    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: CodyCategoryTint? = nil,
        showsDisclosure: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.init(
            title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            showsDisclosure: showsDisclosure,
            trailing: { EmptyView() },
            destination: destination
        )
    }
}

/// Outlined-capsule Settings action/button row.
struct CodySettingsNovaActionRow<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String?
    let tint: CodyCategoryTint?
    let isDestructive: Bool
    let showsDisclosure: Bool
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: CodyCategoryTint? = nil,
        isDestructive: Bool = false,
        showsDisclosure: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.isDestructive = isDestructive
        self.showsDisclosure = showsDisclosure
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            CodySettingsNovaRowContent(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: isDestructive ? .red : tint,
                titleColor: isDestructive ? CodyColors.statusErrorText : CodyColors.textPrimary,
                showsDisclosure: showsDisclosure,
                trailing: trailing
            )
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}

extension CodySettingsNovaActionRow where Trailing == EmptyView {
    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: CodyCategoryTint? = nil,
        isDestructive: Bool = false,
        showsDisclosure: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            isDestructive: isDestructive,
            showsDisclosure: showsDisclosure,
            action: action,
            trailing: { EmptyView() }
        )
    }
}

/// Outlined-capsule Settings toggle row (monochrome optional leading icon + right-aligned switch).
struct CodySettingsNovaToggleRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String?
    let tint: CodyCategoryTint?
    @Binding var isOn: Bool

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: CodyCategoryTint? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(CodyColors.iconPrimary)
                    .frame(width: 24, height: 24, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
                Text(title)
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                }
            }
            Spacer(minLength: CodySpacing.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 56 : 70, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Shared layout body for outlined-capsule settings rows (monochrome line icon, airy 56pt/70pt row height, delicate chevron).
struct CodySettingsNovaRowContent<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String?
    let tint: CodyCategoryTint?
    var titleColor: Color = CodyColors.textPrimary
    var showsDisclosure: Bool = true
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(titleColor == CodyColors.statusErrorText ? CodyColors.statusErrorText : CodyColors.iconPrimary)
                    .frame(width: 24, height: 24, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(CodyTypography.bodySmall)
                        .foregroundStyle(CodyColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: CodySpacing.sm)
            trailing()
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodyColors.iconDisclosure.opacity(0.75))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, subtitle == nil ? 14 : 13)
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil ? 56 : 70,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}

/// Compact hero account/soul row usable inside the top outlined capsule card (avatar on left, label, trailing name + chevron).
struct CodySettingsProfileCard<Avatar: View, Destination: View>: View {
    let name: String
    let subtitle: String
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CodySettingsHairline.capsuleRadius, style: .continuous)
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                avatar()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())

                Text(name)
                    .font(CodyTypography.bodyLarge)
                    .foregroundStyle(CodyColors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: CodySpacing.sm)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CodyTypography.bodyLarge)
                        .foregroundStyle(CodyColors.textSecondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodyColors.iconDisclosure.opacity(0.75))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(shape.fill(CodySettingsHairline.cardFill))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodySettingsHairline.strokeColor, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}
