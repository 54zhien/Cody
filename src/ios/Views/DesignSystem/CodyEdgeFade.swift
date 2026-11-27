import SwiftUI
import UIKit

private enum CodyEdgeFadeRamp {
    static let locations: [CGFloat] = [0, 0.12, 0.24, 0.36, 0.46, 0.55, 1]
    static let topAlphas: [CGFloat] = [1, 0.82, 0.50, 0.18, 0.04, 0, 0]
}

final class CodyEdgeFadeOverlay: UIView {
    enum Direction {
        /// Starts opaque at the top and fades toward the bottom.
        case top
        /// Starts transparent at the top and becomes opaque toward the bottom.
        case bottom

        fileprivate var alphas: [CGFloat] {
            switch self {
            case .top: return CodyEdgeFadeRamp.topAlphas
            case .bottom: return CodyEdgeFadeRamp.topAlphas.map { 1 - $0 }
            }
        }
    }

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }
    private let direction: Direction

    var color: UIColor {
        didSet { restyle() }
    }

    init(direction: Direction, color: UIColor = CodyUIColors.bgCanvas) {
        self.direction = direction
        self.color = color
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.locations = CodyEdgeFadeRamp.locations.map { NSNumber(value: Double($0)) }
        if #available(iOS 17.0, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
                (view: CodyEdgeFadeOverlay, _: UITraitCollection) in
                view.restyle()
            }
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(direction:color:)")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { restyle() }
    }

    @available(iOS, introduced: 8.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0),
           traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            restyle()
        }
    }

    private func restyle() {
        let pageColor = color.resolvedColor(with: traitCollection).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = direction.alphas.map { alpha in
            pageColor.copy(alpha: pageColor.alpha * alpha) ?? pageColor
        }
        CATransaction.commit()
    }
}

@MainActor
final class CodyTopFadeExtender {
    enum Mode {
        case keepSystemEffect
        case own
    }

    var height: CGFloat {
        didSet { layoutFade() }
    }

    var mode: Mode {
        didSet {
            applyMode()
            layoutFade()
        }
    }

    var color: UIColor {
        get { fade.color }
        set { fade.color = newValue }
    }

    private let fade: CodyEdgeFadeOverlay
    private weak var scrollView: UIScrollView?
    private var restoreSystemEffect: (@MainActor () -> Void)?
    private var barBottom: CGFloat = 0
    private var width: CGFloat = 0

    init(
        height: CGFloat = CodyMetrics.Conversation.topFadeExtraHeight,
        color: UIColor = CodyUIColors.bgCanvas,
        mode: Mode = .keepSystemEffect
    ) {
        self.height = height
        self.mode = mode
        fade = CodyEdgeFadeOverlay(direction: .top, color: color)
        fade.isHidden = true
    }

    /// Insert above the scroll content in the host's coordinate space.
    func install(in host: UIView, above content: UIView, scrollView: UIScrollView) {
        uninstall()
        self.scrollView = scrollView
        host.insertSubview(fade, aboveSubview: content)
        if #available(iOS 26.0, *) {
            let previousStyle = scrollView.topEdgeEffect.style
            let wasHidden = scrollView.topEdgeEffect.isHidden
            restoreSystemEffect = { [weak scrollView] in
                scrollView?.topEdgeEffect.style = previousStyle
                scrollView?.topEdgeEffect.isHidden = wasHidden
            }
        }
        applyMode()
        layoutFade()
    }

    /// Call from viewDidLayoutSubviews with the bar's bottom edge in host coordinates.
    func update(barBottom: CGFloat, width: CGFloat) {
        self.barBottom = barBottom
        self.width = width
        layoutFade()
    }

    func uninstall() {
        restoreSystemEffect?()
        restoreSystemEffect = nil
        scrollView = nil
        fade.removeFromSuperview()
        fade.isHidden = true
    }

    private var effectiveMode: Mode {
        if #available(iOS 26.0, *) { return mode }
        return .own
    }

    private func applyMode() {
        guard #available(iOS 26.0, *), let scrollView else { return }
        scrollView.topEdgeEffect.isHidden = mode == .own
        if mode == .keepSystemEffect {
            scrollView.topEdgeEffect.style = .soft
        }
    }

    private func layoutFade() {
        let y = effectiveMode == .keepSystemEffect ? barBottom : 0
        let end = barBottom + max(0, height)
        let frame = CGRect(x: 0, y: y, width: max(0, width), height: max(0, end - y))
        if fade.frame != frame { fade.frame = frame }
        fade.isHidden = frame.isEmpty
    }
}

extension UIScrollView {
    /// Engage the system effect after the scroll view's first on-screen layout.
    func settleCodyScrollEdgeEffect() {
        guard #available(iOS 26.0, *), window != nil, !isTracking, !isDecelerating else { return }
        let target = contentOffset
        setContentOffset(CGPoint(x: target.x, y: target.y - CodySpacing.px), animated: false)
        setContentOffset(target, animated: false)
    }
}

struct CodyEdgeFadeBar: View {
    let direction: CodyEdgeFadeOverlay.Direction
    let height: CGFloat
    var color: Color = CodyColors.bgCanvas

    var body: some View {
        let stops = zip(CodyEdgeFadeRamp.locations, direction.alphas).map { location, alpha in
            Gradient.Stop(color: color.opacity(Double(alpha)), location: location)
        }
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
