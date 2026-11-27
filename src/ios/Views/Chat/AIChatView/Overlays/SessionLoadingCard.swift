//
//  SessionLoadingCard.swift
//  Cody - chat page (AIChatView)
//
//  LoadingDotsView (the three-dot loading indicator used across the session
//  entry path) and SessionLoadingCard (shown while a session's messages load).
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI

// MARK: - Session Loading Card

/// Three-dot carousel indicator: dots pulse in a staggered wave. The single
/// loading language for the session-entry path (loading card, in-place reload,
/// kernel boot) — replaces every system ProgressView spinner there, so the
/// old system spinner never appears after / alongside the new loading UI.
struct LoadingDotsView: View {
    var dotSize: CGFloat = 10
    var color: Color = CodyColors.iconSecondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(reduceMotion ? 0.85 : (animating ? 1.0 : 0.55))
                    .opacity(reduceMotion ? 0.65 : (animating ? 0.95 : 0.3))
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear {
            if !reduceMotion {
                animating = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Calm skeleton + shimmering status card shown while ENTERING a session whose
/// messages haven't loaded yet. Respects Reduce Motion via CodySkeletonView
/// and CodyShimmeringText.
struct SessionLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CodySpacing.md) {
            HStack(spacing: CodySpacing.sm) {
                LoadingDotsView(dotSize: CodySpacing.xsPlus, color: CodyColors.iconSecondary)
                    .frame(height: CodySpacing.lg)
                CodyShimmeringText("Loading…")
                    .font(CodyTypography.labelLarge)
            }
            VStack(alignment: .leading, spacing: CodySpacing.sm) {
                CodySkeletonView(height: CodySpacing.md, cornerRadius: CodyRadius.sm)
                CodySkeletonView(width: 180, height: CodySpacing.md, cornerRadius: CodyRadius.sm)
            }
        }
        .padding(CodySpacing.lg)
        .frame(maxWidth: 260, alignment: .leading)
        .modifier(CodySurfaceModifier(radius: CodyRadius.surface))
        .accessibilityElement(children: .combine)
    }
}
