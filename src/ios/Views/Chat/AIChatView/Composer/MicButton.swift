//
//  MicButton.swift
//  Cody - chat page (AIChatView)
//
//  The composer's mic button: starts voice input on touch release (finger
//  lift) so a brushing touch does not activate it.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import AVFoundation
import AVKit
import Combine
import GameController
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

// MARK: - Mic Button (touch-release activation)

/// Mic button that triggers on touch-release (finger lift) to avoid accidental activation.
/// Press highlight is provided via GestureState.
struct MicButton: View {
    @ObservedObject var speechManager: SpeechRecognitionManager
    @Binding var inputFocused: Bool
    /// Opens the voice-input (VAD) panel on quick tap or upward lock.
    var onTap: () -> Void = {}
    /// Called if the user holds to dictate and slides left to cancel, passing the cancelled
    /// recognized text so the composer can strip any partial transcript cleanly.
    var onCancelHoldDictation: ((String) -> Void)? = nil
    /// True while inline voice mode is active — the button flips to a keyboard glyph
    /// that switches back to text input.
    var isVoiceActive: Bool = false
    /// Press feedback for the custom-gesture button.
    @State private var micPressed = false
    @State private var isHoldingDictation = false
    @State private var holdTarget: HoldTarget = .finish
    @State private var isTouchDown = false
    @State private var holdArmTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum HoldTarget: Equatable {
        case finish
        case cancel
        case lock
    }

    private static let diameter = CodyMetrics.Composer.buttonVisualSize
    private static let holdThresholdNs: UInt64 = 260_000_000

    private var isRecording: Bool { speechManager.state == .recording }

    var body: some View {
        // Supports both:
        // - Quick tap (release inside within <0.26s, <10pt movement): toggles inline voice mode.
        // - Press-and-hold (>=0.26s): lifts the mic button and starts live dictation;
        //   slide left to cancel, slide up to lock into full voice mode, or release to finish.
        Group {
            if isVoiceActive {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .medium))
            } else {
                CodyIconView(.mic, size: 26)
            }
        }
            .foregroundStyle(glyphForeground)
            .frame(width: Self.diameter, height: Self.diameter)
            .background {
                if isHoldingDictation {
                    Circle()
                        .fill(holdTarget == .cancel ? CodyColors.statusErrorBg : CodyColors.textAccent.opacity(0.18))
                        .overlay {
                            Circle()
                                .strokeBorder(holdTarget == .cancel ? CodyColors.statusErrorText : CodyColors.textAccent, lineWidth: 1.5)
                        }
                } else if isRecording {
                    Circle().fill(CodyColors.statusErrorBg)
                }
            }
            .scaleEffect(isHoldingDictation && !reduceMotion ? 1.22 : 1.0)
            .offset(y: isHoldingDictation && !reduceMotion ? -4 : 0)
            .opacity(micPressed && !isHoldingDictation ? CodyMotion.pressedOpacity : 1)
            .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isRecording)
            .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isVoiceActive)
            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: isHoldingDictation)
            .animation(CodyMotion.resolved(CodyMotion.quick, reduceMotion: reduceMotion), value: holdTarget)
            .overlay(alignment: .topTrailing) {
                if isHoldingDictation {
                    holdStatusBadge
                        .fixedSize()
                        .offset(y: -42)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .contentShape(ComposerControlHitShape())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isTouchDown {
                            isTouchDown = true
                            armHoldDictationIfEligible()
                        }
                        if isHoldingDictation {
                            updateHoldTarget(for: value.translation)
                        } else {
                            let moved = hypot(value.translation.width, value.translation.height)
                            if moved >= 12 {
                                holdArmTask?.cancel()
                                holdArmTask = nil
                            }
                            micPressed = Self.isInside(value.location)
                        }
                    }
                    .onEnded { value in
                        isTouchDown = false
                        holdArmTask?.cancel()
                        holdArmTask = nil
                        micPressed = false

                        if isHoldingDictation {
                            finishHoldDictation()
                            return
                        }

                        let started = Self.isInside(value.startLocation)
                        let ended = Self.isInside(value.location)
                        let moved = hypot(value.translation.width, value.translation.height)
                        guard started, ended, moved < 10 else { return }
                        activate()
                    }
            )
            .onDisappear {
                isTouchDown = false
                holdArmTask?.cancel()
                holdArmTask = nil
                if isHoldingDictation {
                    speechManager.stopRecording()
                    isHoldingDictation = false
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate() }
            .accessibilityLabel(isVoiceActive
                ? Text("Switch to text input", comment: "Mic button exits voice mode")
                : Text("Voice input", comment: "Mic button opens voice panel"))
            .accessibilityHint(isVoiceActive
                ? Text("")
                : Text("Tap for voice panel, or press and hold to dictate"))
    }

    private var glyphForeground: Color {
        if isHoldingDictation {
            return holdTarget == .cancel ? CodyColors.statusErrorText : CodyColors.textAccent
        }
        return isRecording ? CodyColors.statusErrorText : CodyColors.iconPrimary
    }

    private var holdStatusBadge: some View {
        let label: LocalizedStringKey = switch holdTarget {
        case .cancel: "Release to cancel"
        case .lock: "Release to lock voice"
        case .finish: "Slide ← cancel · ↑ lock"
        }
        return Text(label)
            .font(CodyTypography.labelMedium)
            .foregroundStyle(holdTarget == .cancel ? CodyColors.statusErrorText : CodyColors.textPrimary)
            .padding(.horizontal, CodySpacing.smPlus)
            .padding(.vertical, CodySpacing.xsPlus)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(holdTarget == .cancel ? CodyColors.statusErrorText.opacity(0.5) : CodyColors.borderDefault, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }

    private func armHoldDictationIfEligible() {
        holdArmTask?.cancel()
        guard !isVoiceActive && !isRecording else { return }
        holdArmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.holdThresholdNs)
            guard !Task.isCancelled, isTouchDown, !isVoiceActive else { return }
            let granted = await speechManager.requestPermissions()
            guard !Task.isCancelled, isTouchDown, granted else { return }
            do {
                try speechManager.startRecording()
                inputFocused = false
                holdTarget = .finish
                isHoldingDictation = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } catch {
                // Fall back silently if audio session is unavailable.
            }
        }
    }

    private func updateHoldTarget(for translation: CGSize) {
        let next: HoldTarget
        if translation.width <= -52 {
            next = .cancel
        } else if translation.height <= -48 {
            next = .lock
        } else {
            next = .finish
        }
        if next != holdTarget {
            holdTarget = next
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func finishHoldDictation() {
        let target = holdTarget
        let captured = speechManager.recognizedText
        isHoldingDictation = false
        holdTarget = .finish
        speechManager.stopRecording()

        switch target {
        case .cancel:
            speechManager.recognizedText = ""
            onCancelHoldDictation?(captured)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .lock:
            activate()
        case .finish:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Whether a point (in the button's local space) is within the visible circle.
    private func activate() {
        inputFocused = false
        onTap()
    }

    private static func isInside(_ point: CGPoint) -> Bool {
        let frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        return ComposerControlHitShape.bounds(in: frame).contains(point)
    }
}
