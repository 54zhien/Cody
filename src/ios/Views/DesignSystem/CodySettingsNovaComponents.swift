import SwiftUI
import UIKit

/// Full-page ScrollView host for Nova Settings screens.
/// Replaces default SwiftUI `List`/`Form` chrome with 22pt grouped spacing and 27pt bordered cards.
struct CodySettingsScrollPage<Content: View>: View {
    var bottomInset: CGFloat = CodySpacing.xxxl
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CodyMetrics.Settings.sectionGap) {
                content()
            }
            .padding(.horizontal, CodySpacing.lg)
            .padding(.top, CodySpacing.md)
            .padding(.bottom, bottomInset)
        }
        .background(CodyColors.bgGrouped.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }
}

/// Nova Settings 27pt card section with optional section heading and footer.
struct CodySettingsNovaSection<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey? = nil,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(CodyTypography.sectionHeader.weight(.medium))
                    .foregroundStyle(CodyColors.textSecondary)
                    .padding(.horizontal, CodySpacing.lg)
                    .padding(.bottom, 7)
                    .accessibilityAddTraits(.isHeader)
            }

            let shape = RoundedRectangle(cornerRadius: CodyMetrics.Settings.sectionRadius, style: .continuous)
            VStack(spacing: 0) {
                content()
            }
            .background(shape.fill(CodyColors.bgGroupedSurface))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }

            if let footer {
                Text(footer)
                    .font(CodyTypography.bodySmall)
                    .foregroundStyle(CodyColors.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.top, CodySpacing.sm)
            }
        }
    }
}

/// Subtle inset separator between rows inside a `CodySettingsNovaSection`.
struct CodySettingsNovaDivider: View {
    var leadingInset: CGFloat = 56

    var body: some View {
        Rectangle()
            .fill(CodyColors.separator.opacity(0.65))
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

/// Nova Settings navigation row (56pt single-line, 72pt with subtitle).
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
        showsDisclosure: Bool = false,
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
        showsDisclosure: Bool = false,
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

/// Nova Settings button / action row.
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

/// Nova Settings toggle row with optional icon badge and subtitle.
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
        HStack(spacing: CodySpacing.md) {
            if let systemImage {
                CodySettingsIconBadge(systemImage: systemImage, tint: tint)
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
        .padding(.horizontal, CodyMetrics.Settings.rowPaddingH)
        .padding(.vertical, CodySpacing.md)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil ? CodyMetrics.Settings.rowMinHeight : CodyMetrics.Settings.navRowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Shared layout body for Nova settings rows.
struct CodySettingsNovaRowContent<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String?
    let tint: CodyCategoryTint?
    var titleColor: Color = CodyColors.textPrimary
    var showsDisclosure: Bool = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CodySpacing.md) {
            if let systemImage {
                CodySettingsIconBadge(systemImage: systemImage, tint: tint)
            }
            VStack(alignment: .leading, spacing: CodySpacing.xxs) {
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
                    .font(.system(size: CodyMetrics.Settings.disclosureSize, weight: .semibold))
                    .foregroundStyle(CodyColors.iconDisclosure)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, CodyMetrics.Settings.rowPaddingH)
        .padding(.vertical, subtitle == nil ? CodySpacing.mdPlus : CodySpacing.md)
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil ? CodyMetrics.Settings.rowMinHeight : CodyMetrics.Settings.navRowMinHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}

/// Top hero identity card for Nova Settings (displays Soul avatar/emoji, name, and active model summary).
struct CodySettingsProfileCard<Avatar: View, Destination: View>: View {
    let name: String
    let subtitle: String
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CodyMetrics.Settings.sectionRadius, style: .continuous)
        NavigationLink(destination: destination) {
            HStack(spacing: CodySpacing.mdPlus) {
                avatar()
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(CodyColors.bgListIcon))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(CodyTypography.titleLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(CodyTypography.bodyMedium)
                        .foregroundStyle(CodyColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: CodySpacing.sm)

                Image(systemName: "chevron.forward")
                    .font(.system(size: CodyMetrics.Settings.disclosureSize, weight: .semibold))
                    .foregroundStyle(CodyColors.iconDisclosure)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, CodySpacing.lg)
            .padding(.vertical, CodySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(CodyColors.bgGroupedSurface))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
        }
        .buttonStyle(CodyPressableButtonStyle())
    }
}
