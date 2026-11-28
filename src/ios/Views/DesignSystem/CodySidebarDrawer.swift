import SwiftUI
import UIKit

/// Full-screen live-blurred sidebar overlay matching the Nova reference:
/// - Swiping right from the left 24pt edge (or tapping the drawer button) blurs the entire
///   underlying canvas cleanly and overlays a true translucent blur veil (never opaque white),
///   letting underlying chat artwork, bubbles, and colors shine softly through in both Light & Dark modes.
/// - Release threshold: velocity >= 620 opens, <= -620 closes, else progress >= 0.5.
/// - Settle animation: spring(stiffness: 460, damping: 38).
struct CodySidebarDrawer<Content: View, Drawer: View>: View {
    @Binding var isOpen: Bool
    var edgeDragEnabled: Bool = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let drawer: () -> Drawer

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var dragProgress: CGFloat? = nil
    @State private var dragStartProgress: CGFloat = 0

    private static var velocityThreshold: CGFloat { 620 }
    private static var progressThreshold: CGFloat { 0.5 }

    private var effectiveProgress: CGFloat {
        if let dragProgress {
            return min(max(dragProgress, 0), 1)
        }
        return isOpen ? 1 : 0
    }

    var body: some View {
        GeometryReader { geo in
            let dragSpan = max(min(geo.size.width * 0.78, 340), 220)
            let progress = effectiveProgress
            let contentShiftX = ((progress - 1) * 44).rounded()

            ZStack(alignment: .leading) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: reduceTransparency ? 0 : progress * 16)
                    .allowsHitTesting(progress < 0.05)

                // Left-edge drag hotzone when drawer is closed (inset from top navbar and bottom chrome
                // so it never intercepts taps on the drawer button, composer "+", or bottom Home tab).
                if edgeDragEnabled && !isOpen && progress < 0.05 {
                    Color.clear
                        .frame(width: CodyMetrics.Sidebar.edgeWidth)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 88)
                        .contentShape(Rectangle())
                        .gesture(drawerDragGesture(dragSpan: dragSpan))
                        .accessibilityHidden(true)
                }

                // Full-screen translucent blur backdrop + frameless drawer content
                if progress > 0.001 || isOpen {
                    ZStack(alignment: .leading) {
                        Group {
                            if reduceTransparency {
                                CodyColors.bgPrimary
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .opacity(colorScheme == .dark ? 0.86 : 0.72)
                                    (colorScheme == .dark
                                        ? Color.black.opacity(0.24)
                                        : Color.black.opacity(0.04))
                                }
                            }
                        }
                        .ignoresSafeArea()
                        .opacity(Double(progress))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settle(open: false)
                        }

                        drawer()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .offset(x: contentShiftX)
                            .opacity(Double(progress))
                    }
                    .simultaneousGesture(drawerDragGesture(dragSpan: dragSpan))
                    .accessibilityAddTraits(.isModal)
                }
            }
            .animation(
                dragProgress == nil ? CodyMotion.resolved(CodyMotion.drawer, reduceMotion: reduceMotion) : nil,
                value: isOpen
            )
        }
    }

    private func drawerDragGesture(dragSpan: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragProgress == nil {
                    guard abs(dx) > abs(dy) else { return }
                    if !isOpen && dx <= 0 { return }
                    dragStartProgress = isOpen ? 1 : 0
                }
                let next = min(max(dragStartProgress + dx / dragSpan, 0), 1)
                dragProgress = next
            }
            .onEnded { value in
                guard let current = dragProgress else { return }
                let predictedDelta = value.predictedEndTranslation.width - value.translation.width
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
