import SwiftUI

// MARK: - Waveform animation (shown while recording)

struct VoiceWaveformView: View {
    let levels: [Float]  // 0...1, one per bar
    var tint = CodyColors.iconPrimary
    var height: CGFloat = CodySpacing.xxxl

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: CodySpacing.xxs) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint)
                    .frame(width: CodySpacing.xxs, height: max(CodySpacing.xs, CGFloat(level) * height))
                    .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: level)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
