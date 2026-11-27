//  TextFadeAnimator.swift
//  Cody
//
//  Word-by-word fade-in animation for streaming Markdown output.
//
//  When the renderer appends new tokens to a message's textStorage via the
//  `[AttachHotPath]` append-only fast path in SelectableMarkdownView, instead
//  of the new glyphs popping in instantly we fade each word from alpha 0 → 1
//  with a small per-word stagger, producing a "ripple" reveal.
//
//  Design constraints:
//   - Display-layer only. Does NOT touch CodyMarkdownParser / AST /
//     MarkdownNSRenderer. We mutate the live NSTextStorage's `.foregroundColor`
//     attribute and rely on TextKit 1's behaviour that a foregroundColor change
//     does NOT invalidate layout (no `ensureLayout` reflow) — only a redraw.
//   - O(new words), never O(full text). Only the appended NSRange is scanned.
//   - A single CADisplayLink drives ALL in-flight words; it stops itself once
//     every word has settled, so an idle (non-streaming) view costs nothing.
//
//  This file deliberately owns no parsing or rendering logic; it is a pure
//  per-word color scheduler over an existing NSTextStorage.

import UIKit

/// Drives word-by-word alpha fade-in for newly appended text in an
/// NSTextStorage. Lives on the SelectableMarkdownView Coordinator; one
/// instance per on-screen textView.
@MainActor
final class TextFadeAnimator {

    // MARK: - Tunables

    /// Hard cap on how many reveal units (words + inter-word gaps) a single
    /// schedule call will animate. A large paste (or a big non-streaming
    /// append) would otherwise schedule hundreds of fades on one frame; above
    /// this we skip the animation entirely and let the text appear instantly.
    /// Streaming appends are only a handful of units per call, so this never
    /// trips during normal output. Raised from 80 since each word now also
    /// contributes its trailing-gap unit (~2× the count for the same text).
    private static let maxAnimatedWords = 160

    /// Bound each batch's stagger so a burst settles alongside subsequent appends.
    private static let staggerWindow: CFTimeInterval = 0.10

    // MARK: - State

    private struct ColorRun {
        let range: NSRange
        let originalColor: UIColor
    }

    private struct FadeWord {
        let range: NSRange
        let startTime: CFTimeInterval
        let colors: [ColorRun]
    }

    private let preset: CodyMotion.StreamingPreset
    private let highlight: UIColor?

    /// The storage we mutate. Weak — the textView (and its storage) outlives
    /// us via the Coordinator, but we never want to keep it alive ourselves.
    private weak var storage: NSTextStorage?
    /// Called after each frame's attribute mutation so the textView repaints.
    /// Weak capture lives in the closure the owner supplies.
    private let requestRedraw: () -> Void

    private var words: [FadeWord] = []
    private var displayLink: CADisplayLink?

    // MARK: - Init

    /// - Parameter requestRedraw: invoked on the main thread after each frame's
    ///   alpha mutation. The owner should call `textView.setNeedsDisplay()`.
    init(preset: CodyMotion.StreamingPreset = .enhanced, requestRedraw: @escaping () -> Void) {
        self.preset = preset
        self.requestRedraw = requestRedraw
        switch preset {
        case .enhanced, .snappy: highlight = CodyUIColors.streamingHighlight
        case .neutral: highlight = CodyUIColors.thinkingNeutral
        case .fallback: highlight = nil
        }
    }

    deinit {
        // CADisplayLink retains its target; we invalidate in cancelAll, but
        // guard here too in case the owner is torn down mid-animation.
        displayLink?.invalidate()
    }

    // MARK: - Scheduling

    /// Begin fading the words inside `range` of `targetStorage` from alpha 0 → 1.
    ///
    /// Call this from the append-only fast path AFTER `replaceCharacters`, with
    /// the NSRange of the freshly-appended tail. Safe to call repeatedly while
    /// streaming — each call adds its words to the shared in-flight set.
    func scheduleAnimation(for range: NSRange, in targetStorage: NSTextStorage) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            if !words.isEmpty { cancelAll() }
            return
        }
        guard range.length > 0 else { return }
        let storageLen = targetStorage.length
        // Defensive clamp: the caller computed `range` from the same storage,
        // but a racing edit could have shrunk it. Never index out of bounds.
        guard range.location >= 0, range.location < storageLen else { return }
        let safeRange = NSRange(
            location: range.location,
            length: min(range.length, storageLen - range.location)
        )
        guard safeRange.length > 0 else { return }

        if storage !== targetStorage && !words.isEmpty { cancelAll() }
        storage = targetStorage

        // Split the appended tail into reveal units. Unlike a bare
        // `.byWords` enumeration (which omits the punctuation / whitespace /
        // symbols / emoji BETWEEN words, leaving them to pop in instantly),
        // this also emits the inter-word gaps + leading/trailing separators so
        // EVERY character in the new range fades. Collect ranges before editing
        // so a paste over the cap appears instantly.
        let nsString = targetStorage.string as NSString
        let wordRanges = Self.revealUnits(in: nsString, within: safeRange, cap: Self.maxAnimatedWords)

        // Word count over the cap → skip the animation for this batch. The
        // text is already in the storage at full opacity, so it just appears.
        guard !wordRanges.isEmpty, wordRanges.count <= Self.maxAnimatedWords else { return }

        let baseStart = CACurrentMediaTime()
        let step = min(preset.stagger, Self.staggerWindow / CFTimeInterval(wordRanges.count))

        targetStorage.beginEditing()
        for (index, range) in wordRanges.enumerated() {
            var colors: [ColorRun] = []
            targetStorage.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subrange, _ in
                colors.append(ColorRun(range: subrange, originalColor: value as? UIColor ?? .label))
            }
            words.append(FadeWord(range: range, startTime: baseStart + CFTimeInterval(index) * step, colors: colors))
            for run in colors {
                targetStorage.addAttribute(.foregroundColor, value: run.originalColor.withAlphaComponent(0), range: run.range)
            }
        }
        targetStorage.endEditing()

        requestRedraw()
        startDisplayLinkIfNeeded()
    }

    /// Cancel every in-flight fade and restore full opacity immediately. Called
    /// on a new message, rotation/width change, or any non-append update — the
    /// ranges we hold are no longer valid against the rebuilt storage.
    func cancelAll() {
        stopDisplayLink()
        // Snap any partially-faded words to their final color so nothing is
        // left stuck translucent. Only safe while `storage` still holds the
        // ranges we recorded; on a full replace the caller has already swapped
        // storage, in which case the ranges are stale and we simply drop them.
        if let storage, !words.isEmpty {
            let len = storage.length
            storage.beginEditing()
            for word in words where NSMaxRange(word.range) <= len {
                Self.restore(word, in: storage)
            }
            storage.endEditing()
            requestRedraw()
        }
        words.removeAll(keepingCapacity: true)
    }

    // MARK: - Frame loop

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, !words.isEmpty else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        // Allow the system to pick within 30–120Hz, preferring 60. The fade is
        // smooth at 30 and we don't need to force 120Hz battery cost.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            cancelAll()
            return
        }
        guard let storage else {
            stopDisplayLink()
            words.removeAll(keepingCapacity: true)
            return
        }
        let now = CACurrentMediaTime()
        let storageLen = storage.length

        let duration = preset.duration
        let delay = preset.colorDelay
        let highlight = self.highlight
        storage.beginEditing()
        words.removeAll { word in
            guard NSMaxRange(word.range) <= storageLen else { return true }
            let elapsed = now - word.startTime
            guard elapsed > 0 else { return false }
            if elapsed >= duration {
                Self.restore(word, in: storage)
                return true
            }

            let progress = elapsed / duration
            let opacity: CGFloat
            let tintAmount: CGFloat
            if let delay {
                let reveal = min(1, progress / 0.18)
                opacity = CGFloat(reveal * reveal * (3 - 2 * reveal))
                let settling = max(0, (elapsed - delay) / (duration - delay))
                tintAmount = 0.40 * CGFloat(1 - Self.easeOutCubic(settling))
            } else {
                opacity = CGFloat(Self.easeOutCubic(progress))
                tintAmount = 0
            }
            for run in word.colors {
                let color = Self.revealColor(for: run.originalColor, highlight: highlight, tintAmount: tintAmount, opacity: opacity)
                storage.addAttribute(.foregroundColor, value: color, range: run.range)
            }
            return false
        }
        storage.endEditing()

        requestRedraw()

        if words.isEmpty {
            stopDisplayLink()
        }
    }

    // MARK: - Helpers

    /// ease-out cubic: `1 - (1 - t)³`. Fast start, gentle settle.
    private static func easeOutCubic(_ t: CFTimeInterval) -> CFTimeInterval {
        let inv = 1 - t
        return 1 - inv * inv * inv
    }

    /// Split `range` of `string` into contiguous reveal units that together
    /// cover EVERY character — words PLUS the punctuation / whitespace /
    /// symbol / emoji gaps between and around them. A bare `.byWords`
    /// enumeration skips those gaps, so they'd pop in at full opacity instead
    /// of fading; this mirrors Microsoft SwiftStreamingMarkdown's
    /// `splitIntoWords`, which appends leading / inter-word / trailing gaps as
    /// their own ranges. Returns empty if the unit count would exceed `cap`
    /// (caller then skips the animation for that oversized batch). Falls back
    /// to the whole range as a single unit when no word boundary is found
    /// (e.g. a pure-symbol / emoji-only tail).
    private static func revealUnits(in string: NSString, within range: NSRange, cap: Int) -> [NSRange] {
        var units: [NSRange] = []
        var overflow = false
        let appendGap = { (start: Int, end: Int) in
            if end > start { units.append(NSRange(location: start, length: end - start)) }
        }
        string.enumerateSubstrings(in: range, options: [.byWords, .localized, .substringNotRequired]) { _, wordRange, _, stop in
            // Gap before this word: trailing edge of the previous unit (or the
            // range start) up to the word's start.
            let gapStart = units.last.map { NSMaxRange($0) } ?? range.location
            appendGap(gapStart, wordRange.location)
            units.append(wordRange)
            if units.count > cap { overflow = true; stop.pointee = true }
        }
        if overflow { return [] }
        // Trailing separators after the last word (or the whole range if there
        // were no words at all — pure punctuation / emoji).
        let tailStart = units.last.map { NSMaxRange($0) } ?? range.location
        appendGap(tailStart, NSMaxRange(range))
        if units.count > cap { return [] }
        return units
    }

    private static func restore(_ word: FadeWord, in storage: NSTextStorage) {
        for run in word.colors {
            storage.addAttribute(.foregroundColor, value: run.originalColor, range: run.range)
        }
    }

    private static func revealColor(for original: UIColor, highlight: UIColor?, tintAmount: CGFloat, opacity: CGFloat) -> UIColor {
        UIColor { traits in
            let base = original.resolvedColor(with: traits)
            let alpha = base.cgColor.alpha * opacity
            guard let highlight, tintAmount > 0 else { return base.withAlphaComponent(alpha) }

            let accent = highlight.resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
            guard base.getRed(&r, green: &g, blue: &b, alpha: nil),
                  accent.getRed(&ar, green: &ag, blue: &ab, alpha: nil) else {
                return base.withAlphaComponent(alpha)
            }
            return UIColor(red: r + (ar - r) * tintAmount,
                           green: g + (ag - g) * tintAmount,
                           blue: b + (ab - b) * tintAmount,
                           alpha: alpha)
        }
    }
}
