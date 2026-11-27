import SwiftUI

struct CodySkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat = CodySpacing.lg
    var cornerRadius: CGFloat = CodyRadius.md

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(width: CGFloat? = nil, height: CGFloat = CodySpacing.lg, cornerRadius: CGFloat = CodyRadius.md) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(CodyColors.loadingBg)
            .frame(width: width, height: height)
            .overlay {
                if !reduceMotion && scenePhase == .active {
                    CodyShimmerBand(color: CodyColors.loadingFg)
                }
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct CodyShimmeringText: View {
    private let text: Text
    private let baseColor: Color
    private let highlightColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(_ text: Text, baseColor: Color = CodyColors.textSecondary, highlightColor: Color = CodyColors.textPrimary) {
        self.text = text
        self.baseColor = baseColor
        self.highlightColor = highlightColor
    }

    init(_ title: LocalizedStringKey, baseColor: Color = CodyColors.textSecondary, highlightColor: Color = CodyColors.textPrimary) {
        self.init(Text(title), baseColor: baseColor, highlightColor: highlightColor)
    }

    var body: some View {
        text.foregroundStyle(baseColor)
            .overlay {
                if !reduceMotion && scenePhase == .active {
                    text.foregroundStyle(highlightColor)
                        .mask { CodyShimmerBand(color: .white, peakOpacity: 1.0) }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct CodyShimmerBand: View {
    let color: Color
    var peakOpacity: Double = CodyMotion.skeletonBandOpacity
    @State private var startTime = Date()

    var body: some View {
        TimelineView(.animation) { context in
            if let progress = sweepProgress(at: context.date) {
                GeometryReader { geometry in
                    band(in: geometry.size, progress: progress)
                }
            }
        }
    }

    private func sweepProgress(at date: Date) -> CGFloat? {
        let elapsed = date.timeIntervalSince(startTime) - CodyMotion.shimmerInitialDelaySeconds
        guard elapsed >= 0 else { return nil }
        let phase = elapsed.truncatingRemainder(dividingBy: CodyMotion.shimmerCycleSeconds)
        let sweepDuration = CodyMotion.shimmerCycleSeconds - CodyMotion.shimmerRestSeconds
        guard phase < sweepDuration else { return nil }
        return CGFloat(phase / sweepDuration)
    }

    private func band(in size: CGSize, progress: CGFloat) -> some View {
        let tilt: Angle = .degrees(18)
        let cosine = CGFloat(cos(tilt.radians))
        let tangent = CGFloat(tan(tilt.radians))
        let bandWidth = max(size.width * 0.42, CodySpacing.md)
        // Move the rotated strip fully outside both edges before restarting the sweep.
        let overhang = (bandWidth / cosine + size.height * tangent) / 2
        let x = progress * (size.width + 2 * overhang) - overhang

        return LinearGradient(
            colors: [color.opacity(0), color.opacity(peakOpacity), color.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth, height: size.height / cosine + bandWidth * tangent)
        .rotationEffect(tilt)
        .position(x: x, y: size.height / 2)
    }
}
