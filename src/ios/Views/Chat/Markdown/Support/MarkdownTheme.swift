//
//  MarkdownTheme.swift
//  Cody - markdown renderer module (Views/Chat/Markdown)
//
//  Visual vocabulary of rendered markdown.
//
//  - NSAttributedString.Key extensions: attributes the renderer writes and
//    CodyLayoutManager / the text view read back (inline code background and
//    text, blockquote depth).
//  - codyInlineCodeBackgroundColor: the single source of the inline-code pill
//    colour, shared by the theme, CodyLayoutManager (the paint site) and table
//    cells, so they cannot drift apart.
//  - SelectableMarkdownTheme: UIKit mirror of the `.codyChat` MarkdownUI theme
//    (fonts, colours, spacing). Attachments keep a copy of the theme they were
//    rendered with.
//  - renderMarkdownBlocks: one-shot render for callers outside the view, e.g.
//    AIChatViewModel caching the attributed string of a finished message.
//
//  Module map and conventions: Bridge/SelectableMarkdownView.swift.
//

import AVFoundation
import Combine
import CoreText
import Photos
import SwiftUI
import UIKit

// MARK: - Custom Attributed String Keys

extension NSAttributedString.Key {
    static let inlineCodeBackground = NSAttributedString.Key("codyInlineCodeBackground")
    static let inlineCodeText = NSAttributedString.Key("codyInlineCodeText")
    static let blockquoteDepth = NSAttributedString.Key("codyBlockquoteDepth")
}

// MARK: - SelectableMarkdownTheme

/// [T-inline-code-dark-bg-ios] Shared by the theme, layout manager, and table cells.
let codyInlineCodeBackgroundColor = CodyUIColors.bgInlineCode

/// Mirrors the `.codyChat` MarkdownUI theme using UIKit types.
struct SelectableMarkdownTheme {
    let baseFontSize: CGFloat
    let codeBlockCornerRadius = CodyRadius.control
    let inlineCodeCornerRadius: CGFloat = 5

    init(baseFontSize: CGFloat? = nil) {
        self.baseFontSize = baseFontSize ?? 16.5
    }

    var baseFont: UIFont { .systemFont(ofSize: baseFontSize) }
    var labelColor: UIColor { .label }
    var secondaryLabelColor: UIColor { .secondaryLabel }
    var accentColor: UIColor { .systemOrange }
    var linkColor: UIColor { CodyUIColors.textLink }
    var codeBlockBackground: UIColor { CodyUIColors.bgCodeBlock }
    var codeBlockTextColor: UIColor { CodyUIColors.syntaxDefault }
    var inlineCodeBackground: UIColor { codyInlineCodeBackgroundColor }
    var inlineCodeColor: UIColor { .systemOrange }
    var blockquoteBarColor: UIColor { CodyUIColors.borderHeavy }
    var tableBorderColor: UIColor { CodyUIColors.borderDefault }

    func headingFont(level: Int) -> UIFont {
        let size: CGFloat
        let weight: UIFont.Weight
        switch level {
        case 1: size = baseFontSize * 1.5; weight = .bold
        case 2: size = baseFontSize * 1.3; weight = .bold
        case 3: size = baseFontSize * 1.15; weight = .semibold
        case 5: size = baseFontSize * 0.875; weight = .semibold
        case 6: size = baseFontSize * 0.85; weight = .semibold
        default: size = baseFontSize; weight = .semibold // H4 and fallback
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    var inlineCodeFont: UIFont { inlineCodeFont(matching: nil) }

    /// [T-md-inline-code-context-font] Inline code sized RELATIVE to the text
    /// it sits in — 0.845× the CONTEXT font, the exact ratio body text has
    /// always used (0.845 × baseFontSize), so paragraph rendering is
    /// unchanged while a code span inside an H1/H2 scales with the heading
    /// instead of rendering at body size and reading sunken/undersized.
    func inlineCodeFont(matching contextFont: UIFont?) -> UIFont {
        let size = (contextFont?.pointSize ?? baseFontSize) * 0.845
        if let menlo = UIFont(name: "Menlo", size: size) {
            let descriptor = menlo.fontDescriptor.addingAttributes([
                .cascadeList: [UIFontDescriptor(fontAttributes: [.name: "PingFang SC"])]
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var codeBlockFont: UIFont {
        CodyProseMetrics.monospacedFont(ofSize: baseFontSize * 0.85)
    }
}

/// Renders markdown blocks into an NSAttributedString using a fresh MarkdownNSRenderer.
/// Intended for one-shot rendering of completed messages (e.g. caching in AIChatViewModel).
@MainActor
func renderMarkdownBlocks(_ blocks: [BlockNode]) -> NSAttributedString {
    let renderer = MarkdownNSRenderer(baseFontSize: FontSettings.shared.scaledMessage(16.5))
    return renderer.render(blocks: blocks)
}
