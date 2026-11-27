import SwiftUI

enum CodyMotion {
    static let house = Animation.spring(response: 0.30, dampingFraction: 0.825)
    static let layout = Animation.spring(response: 0.25, dampingFraction: 1.0)
    static let quick = Animation.spring(response: 0.15, dampingFraction: 0.85, blendDuration: 0.25)
    static let promptCard = Animation.spring(response: 0.20, dampingFraction: 0.85)
    static let gentle = Animation.spring(response: 0.50, dampingFraction: 0.85)
    static let plain = Animation.spring(response: 0.50, dampingFraction: 1.0)
    static let drawer = Animation.interpolatingSpring(stiffness: 460, damping: 38)

    static let pressedOpacity: Double = 0.60
    static let disabledOpacity: Double = 0.55
    static let accentBorderAlphaLight: Double = 0.45
    static let accentBorderAlphaDark: Double = 0.90
    static let longPressDuration: Double = 0.35
    static let longPressAllowableMovement: CGFloat = 10
    static let shimmerCycleSeconds: Double = 1.4
    static let shimmerInitialDelaySeconds: Double = 0.304
    static let shimmerRestSeconds: Double = 0.304
    static let skeletonBandOpacity: Double = 0.45

    enum StreamingPreset {
        case enhanced, snappy, neutral, fallback

        var duration: Double { timing.duration }
        var stagger: Double { timing.stagger }
        var colorDelay: Double? { timing.colorDelay }

        private var timing: (duration: Double, stagger: Double, colorDelay: Double?) {
            switch self {
            case .enhanced: return (0.7, 0.035, 0.315)
            case .snappy: return (0.22, 0.03, 0.099)
            case .neutral: return (0.8, 0.06, 0.36)
            case .fallback: return (0.5, 0.07, nil)
            }
        }
    }

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
