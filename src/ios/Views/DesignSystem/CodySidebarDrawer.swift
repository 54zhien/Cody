import SwiftUI
import UIKit

struct CodySidebarDrawer<Content: View, Drawer: View>: View {
    @Binding var isOpen: Bool
    var edgeDragEnabled: Bool = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let drawer: () -> Drawer

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var motion = CodySidebarMotion()
    @State private var dragStart: CGFloat?

    private var backdropRadius: CGFloat {
        guard horizontalSizeClass == .compact else { return 32 }
        return verticalSizeClass == .compact ? 5.5 : 10
    }

    var body: some View {
        GeometryReader { geometry in
            let travelWidth = max(1, min(geometry.size.width * 0.88, 380))
            let visibility = min(1, max(0, motion.progress))
            let showingDrawer = isOpen || visibility > 0

            ZStack(alignment: .leading) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(reduceMotion ? 1 : 1 - visibility * 0.05)
                    .blur(radius: reduceTransparency ? 0 : visibility * 8)
                    .allowsHitTesting(!showingDrawer && dragStart == nil)
                    .accessibilityHidden(showingDrawer)

                if showingDrawer {
                    backdrop
                        .opacity(visibility)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { settle(open: false) }
                        .accessibilityHidden(true)

                    drawer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .offset(x: reduceMotion ? 0 : ((motion.progress - 1) * travelWidth * 2 / 3).rounded())
                        .opacity(visibility)
                        .allowsHitTesting(isOpen && dragStart == nil)
                        .accessibilityAddTraits(.isModal)
                }
            }
            .background {
                CodySidebarPanSurface(
                    isOpen: isOpen,
                    canOpen: edgeDragEnabled,
                    onBegin: {
                        motion.interrupt()
                        dragStart = min(1, max(0, motion.progress))
                    },
                    onMove: { translation in
                        if let dragStart {
                            motion.drag(to: dragStart + translation / travelWidth)
                        }
                    },
                    onEnd: { velocity, cancelled in
                        guard dragStart != nil else { return }
                        let open: Bool
                        if cancelled { open = isOpen }
                        else if velocity >= 620 { open = true }
                        else if velocity <= -620 { open = false }
                        else { open = motion.progress >= 0.5 }
                        settle(open: open)
                    }
                )
                .accessibilityHidden(true)
            }
        }
        .onAppear { motion.synchronize(open: isOpen) }
        .onChange(of: isOpen) { open in
            dragStart = nil
            motion.settle(open: open, immediate: reduceMotion)
        }
        .onDisappear {
            dragStart = nil
            motion.interrupt()
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if reduceTransparency {
            CodyColors.bgPrimary
        } else {
            ZStack {
                CodySidebarBlurSurface(radius: backdropRadius)
                    .id(backdropRadius)
                LinearGradient(
                    stops: [
                        .init(color: colorScheme == .dark ? .black.opacity(0.30) : .white.opacity(0.24), location: 0),
                        .init(color: colorScheme == .dark ? .black.opacity(0.20) : .white.opacity(0.12), location: 0.80),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.80),
                        .init(color: CodyColors.bgCanvas.opacity(0.06), location: 0.95),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
    }

    private func settle(open: Bool) {
        dragStart = nil
        motion.settle(open: open, immediate: reduceMotion)
        if isOpen != open {
            isOpen = open
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

private struct CodySidebarBlurSurface: UIViewRepresentable {
    let radius: CGFloat

    func makeUIView(context: Context) -> CodyVariableBlurView {
        CodyVariableBlurView(radius: radius, ramp: .sidebar)
    }

    func updateUIView(_ view: CodyVariableBlurView, context: Context) {}
}

/// Drives the same displayed progress for the panel and its backdrop. Dragging
/// can interrupt a settling frame, so the next gesture starts where it was drawn.
@MainActor
private final class CodySidebarMotion: NSObject, ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var springStartTime: CFTimeInterval = 0
    private var start: CGFloat = 0
    private var target: CGFloat = 0
    private let settleDuration: CFTimeInterval = 0.30

    func synchronize(open: Bool) {
        interrupt()
        progress = open ? 1 : 0
    }

    func drag(to rawProgress: CGFloat) {
        let boundary = min(1, max(0, rawProgress))
        let excess = rawProgress - boundary
        progress = boundary + excess * 0.10 / (0.25 + abs(excess))
    }

    func interrupt() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func settle(open: Bool, immediate: Bool) {
        let destination: CGFloat = open ? 1 : 0
        if immediate || abs(progress - destination) < 0.001 {
            synchronize(open: open)
            return
        }
        guard displayLink == nil || target != destination else { return }
        interrupt()
        start = progress
        target = destination
        springStartTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(advance(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func advance(_ link: CADisplayLink) {
        let elapsed = max(0, link.targetTimestamp - springStartTime)
        guard elapsed < settleDuration else {
            progress = target
            interrupt()
            return
        }
        // Critically damped, with the reference's time-scaled natural frequency.
        let phase = elapsed * 31.416
        progress = target + (start - target) * CGFloat((1 + phase) * exp(-phase))
    }
}

private struct CodySidebarPanSurface: UIViewRepresentable {
    let isOpen: Bool
    let canOpen: Bool
    let onBegin: () -> Void
    let onMove: (CGFloat) -> Void
    let onEnd: (CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> PanSurface {
        let view = PanSurface()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PanSurface, context: Context) {
        view.configuration = self
    }

    static func dismantleUIView(_ view: PanSurface, coordinator: ()) {
        view.detach()
    }

    final class PanSurface: UIView, UIGestureRecognizerDelegate {
        var configuration: CodySidebarPanSurface?
        private weak var gestureHost: UIView?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                detach()
                return
            }
            guard gestureHost == nil, let host = hostingView() else { return }
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            host.addGestureRecognizer(pan)
            gestureHost = host
        }

        func detach() {
            gestureHost?.removeGestureRecognizer(pan)
            gestureHost = nil
        }

        private func hostingView() -> UIView? {
            // Attach to the containing UIKit surface so changing SwiftUI
            // opacity or mounting the drawer cannot replace an active pan.
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController { return controller.view }
                responder = current.next
            }
            return superview
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let configuration, gestureRecognizer === pan else { return true }
            let velocity = pan.velocity(in: self)
            guard abs(velocity.x) > abs(velocity.y) else { return false }

            let point = pan.location(in: self)
            let translation = pan.translation(in: self)
            let origin = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            guard bounds.contains(origin) else { return false }
            if configuration.isOpen { return velocity.x < 0 }
            return configuration.canOpen && velocity.x > 0 && origin.x < 24
                && origin.y >= 72 && origin.y <= bounds.height - 110
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            guard let configuration else { return }
            switch recognizer.state {
            case .began:
                configuration.onBegin()
                configuration.onMove(recognizer.translation(in: self).x)
            case .changed:
                configuration.onMove(recognizer.translation(in: self).x)
            case .ended:
                configuration.onMove(recognizer.translation(in: self).x)
                configuration.onEnd(recognizer.velocity(in: self).x, false)
            case .cancelled, .failed:
                configuration.onEnd(0, true)
            default:
                break
            }
        }
    }
}
