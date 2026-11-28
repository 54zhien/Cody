import SwiftUI
import UIKit

/// Customizable icon-only bottom navigation bar sitting over a soft blurred/gradient veil
/// (NOT a Liquid Glass pill bar — only the Composer above it uses Liquid Glass).
///
/// Layout: [Home]  [Custom Pinned Tool 1 ... N]  [More (Explore)]
/// Only the active icon displays a soft translucent oval capsule behind it.
struct CodyNovaTabBar: View {
    @Binding var selection: CodyNovaDestination
    @ObservedObject var tabStore: CodyNovaTabStore
    var onSelectDestination: ((CodyNovaDestination) -> Void)? = nil
    var onReselect: ((CodyNovaDestination) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var activeIndicatorNamespace

    static let barHeight: CGFloat = 52
    static let bottomPadding: CGFloat = 4
    static let totalClearance: CGFloat = barHeight + bottomPadding + 6

    private var allDestinations: [CodyNovaDestination] {
        var items: [CodyNovaDestination] = [.home]
        items.append(contentsOf: tabStore.pinnedTools.map { .tool($0) })
        items.append(.more)
        return items
    }

    var body: some View {
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
                            Capsule()
                                .fill(activePillColor)
                                .frame(width: 58, height: 38)
                                .matchedGeometryEffect(id: "novaActiveTabPill", in: activeIndicatorNamespace)
                        }
                        Image(systemName: iconName(for: dest, selected: isSelected))
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
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
        .padding(.horizontal, CodySpacing.md)
        .padding(.bottom, Self.bottomPadding)
        .background(alignment: .bottom) {
            bottomBlurVeil
        }
    }

    private var activePillColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.14)
        } else {
            return Color.black.opacity(0.07)
        }
    }

    /// Soft blurred gradient veil extending beneath the bottom icon bar into the home indicator safe area.
    @ViewBuilder
    private var bottomBlurVeil: some View {
        let veilHeight: CGFloat = Self.barHeight + 56
        ZStack(alignment: .bottom) {
            if !reduceTransparency {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.75), location: 0.32),
                                .init(color: .black, location: 0.65),
                                .init(color: .black, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            LinearGradient(
                stops: [
                    .init(color: CodyColors.bgCanvas.opacity(0.0), location: 0.0),
                    .init(color: CodyColors.bgCanvas.opacity(reduceTransparency ? 0.98 : 0.65), location: 0.45),
                    .init(color: CodyColors.bgCanvas.opacity(reduceTransparency ? 1.0 : 0.88), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: veilHeight)
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
