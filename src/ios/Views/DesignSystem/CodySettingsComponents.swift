import SwiftUI
import UIKit

struct CodySettingsSectionHeader: View {
    let title: LocalizedStringKey
    var disclosure: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .footnote) private var fontSize = CodyMetrics.Settings.sectionHeaderFontSize
    @ScaledMetric(relativeTo: .footnote) private var lineHeight = CodyMetrics.Settings.sectionHeaderLineHeight
    @ScaledMetric(relativeTo: .footnote) private var disclosureSize = CodyMetrics.Settings.disclosureSize

    init(title: LocalizedStringKey, disclosure: (() -> Void)? = nil) {
        self.title = title
        self.disclosure = disclosure
    }

    var body: some View {
        Group {
            if let disclosure {
                Button(action: disclosure) {
                    label
                }
                .buttonStyle(CodyPressableButtonStyle())
            } else {
                label
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var label: some View {
        HStack(spacing: CodySpacing.sm) {
            Text(title)
                .font(CodyTypography.sectionHeader)
                .foregroundStyle(CodyColors.textSecondary)
                .lineSpacing(max(0, lineHeight - UIFont.systemFont(ofSize: fontSize).lineHeight))

            if disclosure != nil {
                Image(systemName: "chevron.forward")
                    .font(.system(size: disclosureSize, weight: .semibold))
                    .foregroundStyle(CodyColors.iconDisclosure)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: lineHeight, alignment: .leading)
        .padding(.top, CodyMetrics.Settings.sectionHeaderTopSpacing)
        .padding(.bottom, CodyMetrics.Settings.sectionHeaderBottomSpacing)
        .padding(.horizontal, CodyMetrics.Settings.sectionHeaderPaddingH)
        .contentShape(Rectangle())
    }
}

struct CodySettingsCardGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CodyMetrics.Settings.sectionRadius, style: .continuous)
        VStack(spacing: 0) {
            content
        }
        .background(shape.fill(CodyColors.bgGroupedSurface))
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                .allowsHitTesting(false)
        }
    }
}

struct CodySettingsRowSurface: ViewModifier {
    var minHeight: CGFloat = CodyMetrics.Settings.rowMinHeight

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CodyMetrics.Settings.rowPaddingH)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .listRowSeparator(.hidden)
            .listRowBackground(CodyColors.bgGroupedSurface)
    }
}

struct CodySettingsIconBadge: View {
    let systemImage: String
    var tint: CodyCategoryTint? = nil
    var outline: CodyListIconBadge.Outline = .roundedSquare

    var body: some View {
        CodyListIconBadge(systemImage: systemImage, tint: tint, outline: outline)
    }
}
