import SwiftUI
import UIKit

/// Compact customizable icon-only bottom bar (`Home` · pinned custom tools · `More`).
///
/// Design rules:
/// - Compact 40pt silhouette flush with the home-indicator safe area (no tall outer dock).
/// - NO outer Liquid Glass capsule wrapping the whole bar — ONLY the active tab's selection pill
///   uses iOS 26 native Liquid Glass morphing (`GlassEffectContainer` + `.glassEffect` + `.glassEffectID`).
/// - NO upward-spilling opaque veil drawn on top of the Composer above it: scroll-edge softening
///   is handled natively by the underlying scroll view (`bottomEdgeEffect.style = .soft` / `.scrollEdgeEffectStyle(.soft, for: .bottom)`).
struct CodyNovaTabBar: View {
    @Binding var selection: CodyNovaDestination
    @ObservedObject var tabStore: CodyNovaTabStore
    var onSelectDestination: ((CodyNovaDestination) -> Void)? = nil
    var onReselect: ((CodyNovaDestination) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var activeIndicatorNamespace

    static let barHeight: CGFloat = 40
    static let bottomPadding: CGFloat = 0
    static let totalClearance: CGFloat = barHeight

    private var allDestinations: [CodyNovaDestination] {
        var items: [CodyNovaDestination] = [.home]
        items.append(contentsOf: tabStore.pinnedTools.map { .tool($0) })
        items.append(.more)
        return items
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *), !MacOS27GlassWorkaround.isActive, !reduceTransparency {
                GlassEffectContainer(spacing: 12) {
                    iconRow(usesLiquidGlassIndicator: true)
                }
            } else {
                iconRow(usesLiquidGlassIndicator: false)
                    .background(alignment: .bottom) {
                        legacyBottomFade
                    }
            }
        }
        .padding(.horizontal, CodySpacing.md)
        .padding(.bottom, Self.bottomPadding)
    }

    private func iconRow(usesLiquidGlassIndicator: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(allDestinations) { dest in
                let isSelected = (selection == dest)
                Button {
                    if isSelected {
                        onReselect?(dest)
                    } else {
                        let generator = UISelectionFeedbackGenerator()
                        generator.selectionChanged()
                        if let onSelectDestination {
                            onSelectDestination(dest)
                        } else {
                            withAnimation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion)) {
                                selection = dest
                            }
                        }
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            if usesLiquidGlassIndicator, #available(iOS 26.0, *) {
                                Color.clear
                                    .frame(width: 56, height: 34)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                    .glassEffectID("novaActiveTabPill", in: activeIndicatorNamespace)
                            } else {
                                Capsule()
                                    .fill(activePillColor)
                                    .frame(width: 56, height: 34)
                                    .matchedGeometryEffect(id: "novaActiveTabPill", in: activeIndicatorNamespace)
                            }
                        }
                        Image(systemName: iconName(for: dest, selected: isSelected))
                            .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? CodyColors.iconPrimary : CodyColors.iconSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.barHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodyPressableButtonStyle())
                .accessibilityLabel(accessibilityLabel(for: dest))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private var activePillColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.14)
        } else {
            return Color.black.opacity(0.07)
        }
    }

    /// Legacy iOS 16–25 / Reduce-Transparency backing confined strictly to the tab bar band (never spills onto the Composer).
    private var legacyBottomFade: some View {
        LinearGradient(
            stops: [
                .init(color: CodyColors.bgCanvas.opacity(0.0), location: 0.0),
                .init(color: CodyColors.bgCanvas.opacity(0.88), location: 0.35),
                .init(color: CodyColors.bgCanvas, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Self.barHeight + 16)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    private func iconName(for dest: CodyNovaDestination, selected: Bool) -> String {
        switch dest {
        case .home:
            return selected ? "house.fill" : "house"
        case .tool(let tool):
            return selected ? tool.selectedIconName : tool.iconName
        case .more:
            return selected ? "square.grid.2x2.fill" : "square.grid.2x2"
        }
    }

    private func accessibilityLabel(for dest: CodyNovaDestination) -> Text {
        switch dest {
        case .home: Text("Home")
        case .tool(let tool): Text(tool.title)
        case .more: Text("More")
        }
    }
}
