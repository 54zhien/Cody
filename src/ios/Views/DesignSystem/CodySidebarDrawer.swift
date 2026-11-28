import SwiftUI
import UIKit

/// Slide-over sidebar drawer matching the spec:
/// - Panel width: 88% of viewport, capped at 380pt
/// - Left edge hotzone: 24pt
/// - Main content canvas stays stationary behind a linear `bgScrim` backdrop
/// - Release threshold: velocity >= 620 opens, <= -620 closes, else progress >= 0.5
/// - Settle animation: spring(stiffness: 460, damping: 38)
struct CodySidebarDrawer<Content: View, Drawer: View>: View {
    @Binding var isOpen: Bool
    var edgeDragEnabled: Bool = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let drawer: () -> Drawer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragProgress: CGFloat? = nil
    @State private var dragStartProgress: CGFloat = 0

    private static let velocityThreshold: CGFloat = 620
    private static let progressThreshold: CGFloat = 0.5

    private var effectiveProgress: CGFloat {
        if let dragProgress {
            return min(max(dragProgress, 0), 1)
        }
        return isOpen ? 1 : 0
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(
                geo.size.width * CodyMetrics.Sidebar.panelWidthPercent,
                CodyMetrics.Sidebar.panelMaxWidth
            )
            let progress = effectiveProgress
            let panelOffsetX = ((progress - 1) * panelWidth).rounded()

            ZStack(alignment: .leading) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(progress < 0.05)

                // Left-edge drag hotzone when drawer is closed
                if edgeDragEnabled && !isOpen && progress < 0.05 {
                    Color.clear
                        .frame(width: CodyMetrics.Sidebar.edgeWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(drawerDragGesture(panelWidth: panelWidth))
                        .accessibilityHidden(true)
                }

                // Scrim backdrop over stationary content
                if progress > 0.001 {
                    CodyColors.bgScrim
                        .ignoresSafeArea()
                        .opacity(Double(progress))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settle(open: false)
                        }
                        .gesture(drawerDragGesture(panelWidth: panelWidth))
                        .accessibilityLabel(Text("Close sidebar"))
                        .accessibilityAddTraits(.isButton)
                }

                // Sliding drawer panel
                if progress > 0.001 || isOpen {
                    drawer()
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .background(CodyColors.bgPrimary.ignoresSafeArea())
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(CodyColors.borderLight)
                                .frame(width: CodySpacing.px)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                        }
                        .offset(x: panelOffsetX)
                        .gesture(drawerDragGesture(panelWidth: panelWidth))
                        .accessibilityAddTraits(.isModal)
                }
            }
            .animation(
                dragProgress == nil ? CodyMotion.resolved(CodyMotion.drawer, reduceMotion: reduceMotion) : nil,
                value: isOpen
            )
        }
    }

    private func drawerDragGesture(panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragProgress == nil {
                    guard abs(dx) > abs(dy) else { return }
                    if !isOpen && dx <= 0 { return }
                    dragStartProgress = isOpen ? 1 : 0
                }
                let next = min(max(dragStartProgress + dx / max(panelWidth, 1), 0), 1)
                dragProgress = next
            }
            .onEnded { value in
                guard let current = dragProgress else { return }
                let predictedDelta = value.predictedEndTranslation.width - value.translation.width
                // DragGesture predictedEndTranslation roughly projects ~0.25s ahead
                let estimatedVelocity = predictedDelta * 4
                let shouldOpen: Bool
                if estimatedVelocity >= Self.velocityThreshold {
                    shouldOpen = true
                } else if estimatedVelocity <= -Self.velocityThreshold {
                    shouldOpen = false
                } else {
                    shouldOpen = current >= Self.progressThreshold
                }
                settle(open: shouldOpen)
            }
    }

    private func settle(open: Bool) {
        let changed = (open != isOpen)
        let anim = CodyMotion.resolved(CodyMotion.drawer, reduceMotion: reduceMotion)
        withAnimation(anim) {
            dragProgress = nil
            isOpen = open
        }
        if changed {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
}
