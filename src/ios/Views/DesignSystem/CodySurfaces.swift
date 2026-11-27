import SwiftUI

struct CodySurfaceModifier: ViewModifier {
    var radius: CGFloat = CodyRadius.surface

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(CodyColors.bgElevatedPrimary))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
    }
}

struct CodyAgentCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyMetrics.AgentCard.cornerRadius, style: .continuous)
        content
            .padding(CodyMetrics.AgentCard.padding)
            .background(shape.fill(CodyColors.bgPrimary))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodyColors.borderLight, lineWidth: CodyMetrics.AgentCard.borderWidth)
                    .allowsHitTesting(false)
            }
    }
}

struct CodyPressableButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(CodyPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled,
                reduceMotion: reduceMotion
            ))
    }
}

struct CodyPrimaryCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.pill, style: .continuous)
        configuration.label
            .foregroundStyle(CodyColors.interactivePrimaryLabel)
            .padding(.horizontal, CodySpacing.lg)
            .padding(.vertical, CodySpacing.smPlus)
            .frame(minWidth: CodyControlHeight.standard, minHeight: CodyControlHeight.standard)
            .background(shape.fill(CodyColors.interactivePrimaryBg))
            .clipShape(shape)
            .contentShape(shape)
            .modifier(CodyPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled,
                reduceMotion: reduceMotion
            ))
    }
}

private struct CodyPressFeedback: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool
    let reduceMotion: Bool

    private var opacity: Double {
        guard isEnabled else { return CodyMotion.disabledOpacity }
        return isPressed ? CodyMotion.pressedOpacity : 1
    }

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .animation(CodyMotion.resolved(.easeOut(duration: 0.12), reduceMotion: reduceMotion), value: isPressed)
    }
}

struct CodyListIconBadge: View {
    enum Outline {
        case roundedSquare, circle
    }

    let systemImage: String
    var tint: CodyCategoryTint? = nil
    var outline: Outline = .roundedSquare

    var body: some View {
        Group {
            switch outline {
            case .roundedSquare:
                badge(in: RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous))
            case .circle:
                badge(in: Circle())
            }
        }
        .accessibilityHidden(true)
    }

    private func badge<S: InsettableShape>(in shape: S) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint?.color ?? CodyColors.iconPrimary)
            .frame(width: CodyMetrics.Sidebar.iconSize, height: CodyMetrics.Sidebar.iconSize)
            .background(shape.fill(CodyColors.bgListIcon))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
    }
}

struct CodyProgressBar: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(progress: Double) {
        self.progress = progress
    }

    private var fraction: Double { progress.isNaN ? 0 : min(max(progress, 0), 1) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CodyMetrics.AgentCard.progressRadius, style: .continuous)
        GeometryReader { geometry in
            let fillWidth = fraction > 0
                ? max(CodyMetrics.AgentCard.progressHeight, geometry.size.width * CGFloat(fraction))
                : 0
            shape.fill(CodyColors.interactiveProgressFill)
                .frame(width: min(fillWidth, geometry.size.width), alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(CodyMotion.resolved(CodyMotion.layout, reduceMotion: reduceMotion), value: fraction)
        }
        .frame(height: CodyMetrics.AgentCard.progressHeight)
        .background(shape.fill(CodyColors.bgProgressTrack))
        .background {
            if reduceTransparency {
                shape.fill(CodyColors.bgPrimary)
            }
        }
        .clipShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
