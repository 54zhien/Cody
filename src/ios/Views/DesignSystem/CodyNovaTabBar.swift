import SwiftUI
import UIKit

/// Floating capsule bottom tab bar for the Cody Nova root shell (`Chat` / `Explore` / `Files`).
/// Uses native iOS 26 Liquid Glass when available and falls back to an elevated pill surface on iOS 16-25.
struct CodyNovaTabBar: View {
    @Binding var selection: CodyNovaTab
    var onReselect: ((CodyNovaTab) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var pillNamespace

    static let barHeight: CGFloat = 54
    static let bottomPadding: CGFloat = 8
    static let totalClearance: CGFloat = barHeight + bottomPadding + 8

    var body: some View {
        HStack(spacing: CodySpacing.xs) {
            ForEach(CodyNovaTab.allCases) { tab in
                let selected = (selection == tab)
                Button {
                    if selected {
                        onReselect?(tab)
                    } else {
                        let generator = UISelectionFeedbackGenerator()
                        generator.selectionChanged()
                        withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                            selection = tab
                        }
                    }
                } label: {
                    HStack(spacing: CodySpacing.xsPlus) {
                        Image(systemName: selected ? tab.selectedIconName : tab.iconName)
                            .font(.system(size: 16, weight: selected ? .semibold : .medium))
                        Text(tab.title)
                            .font(CodyTypography.labelLarge)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? CodyColors.textPrimary : CodyColors.textSecondary)
                    .padding(.horizontal, CodySpacing.lg)
                    .frame(minHeight: CodyControlHeight.standard)
                    .background {
                        if selected {
                            Capsule()
                                .fill(CodyColors.interactiveSecondaryBg)
                                .matchedGeometryEffect(id: "novaTabIndicator", in: pillNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(CodySpacing.xs + 1)
        .frame(height: Self.barHeight)
        .modifier(CodyNovaTabBarChrome(reduceTransparency: reduceTransparency))
        .padding(.horizontal, CodySpacing.lg)
        .padding(.bottom, Self.bottomPadding)
    }
}

private struct CodyNovaTabBarChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !reduceTransparency, !MacOS27GlassWorkaround.isActive, #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(Capsule())
        } else {
            content
                .background(
                    Capsule()
                        .fill(CodyColors.bgElevatedPrimary)
                        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
                )
                .overlay {
                    Capsule()
                        .strokeBorder(CodyColors.borderDefault, lineWidth: CodySpacing.px)
                        .allowsHitTesting(false)
                }
        }
    }
}
