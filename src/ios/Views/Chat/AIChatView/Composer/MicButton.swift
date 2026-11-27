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
    /// Opens the voice-input (VAD) panel. The mic button no longer drives the
    /// in-bar SFSpeech live dictation directly — the panel (with the configured
    /// ASR provider, or the offline System fallback) is the single voice entry
    /// point. The SpeechRecognitionManager path stays in place but is no longer
    /// triggered from here.
    var onTap: () -> Void = {}
    /// True while inline voice mode is active — the button flips to a "T" glyph
    /// that switches back to text input.
    var isVoiceActive: Bool = false
    /// Press feedback for the custom-gesture button.
    @State private var micPressed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter = CodyMetrics.Composer.buttonVisualSize

    private var isRecording: Bool { speechManager.state == .recording }

    var body: some View {
        // NOT a Button: SwiftUI's Button has a generous system touch-slop / touch-
        // up tolerance that fires when the finger lifts slightly outside, or moves
        // a little during a scroll/drag — which made this toggle very easy to
        // mis-tap. We use a DragGesture(minimumDistance: 0) and only activate when
        // BOTH the press and release land inside the circle AND movement is tiny.
        // In voice mode: a keyboard glyph = switch back to text input. The keyboard
        // glyph is wider than the mic, so render it ~4pt smaller for parity.
        Image(systemName: isVoiceActive ? "keyboard" : "mic")
            .font(.system(size: isVoiceActive ? 15 : 18, weight: .medium))
            .foregroundStyle(isRecording ? CodyColors.statusErrorText : CodyColors.iconSecondary)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(isRecording ? CodyColors.statusErrorBg : CodyColors.bgListIcon))
            .overlay {
                Circle().strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .opacity(micPressed ? CodyMotion.pressedOpacity : 1)
            .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isRecording)
            .animation(CodyMotion.resolved(CodyMotion.house, reduceMotion: reduceMotion), value: isVoiceActive)
            .contentShape(ComposerControlHitShape())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        micPressed = Self.isInside(value.location)
                    }
                    .onEnded { value in
                        let started = Self.isInside(value.startLocation)
                        let ended = Self.isInside(value.location)
                        let moved = hypot(value.translation.width, value.translation.height)
                        micPressed = false
                        guard started, ended, moved < 10 else { return }
                        activate()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate() }
            .accessibilityLabel(isVoiceActive
                ? Text("Switch to text input", comment: "Mic button exits voice mode")
                : Text("Voice input", comment: "Mic button opens voice panel"))
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
