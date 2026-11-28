//
//  CodeBlockAttachment.swift
//  Cody - markdown renderer module (Views/Chat/Markdown)
//
//  Layer: Attachments.
//
//  Fenced code block: a horizontally scrolling code view with a language
//  header and copy button, sized by attachmentBounds. While a reply streams,
//  each chunk swaps in a fresh attachment at the same character; its content
//  fingerprint is folded into the text view's cell-size fingerprint
//  (SelectableMarkdownTextView+CellSizing) so that growth is not deduplicated
//  away.
//
//  Module map and conventions: Bridge/SelectableMarkdownView.swift.
//

import AVFoundation
import Combine
import CoreText
import Photos
import SwiftUI
import UIKit

// MARK: - Code Block Attachment

final class CodeBlockAttachment: NSTextAttachment {
    var code: String
    let language: String?
    let theme: SelectableMarkdownTheme
    let quoteDepth: Int
    /// Sequential index for view reuse across re-renders (set by MarkdownNSRenderer).
    var blockIndex: Int = 0
    /// [CodeGenDedup] Hash of (code, language), computed once by the renderer
    /// at creation. Folded into the invalidateCellSizeIfNeeded dedupe
    /// fingerprint so in-place code growth during streaming — which changes
    /// neither textStorage.length nor width — still defeats [SKIP-DEDUPE]
    /// and re-invalidates the host cell's height (the TableGenDedup
    /// counterpart for code blocks).
    let contentFingerprint: Int

    /// Left inset for blockquote nesting (matches text indent).
    var leftInset: CGFloat { CGFloat(quoteDepth) * 13 }

    init(code: String, language: String?, theme: SelectableMarkdownTheme, quoteDepth: Int = 0, contentFingerprint: Int = 0) {
        self.code = code
        self.language = language
        self.theme = theme
        self.quoteDepth = quoteDepth
        self.contentFingerprint = contentFingerprint
        super.init(data: nil, ofType: nil)
        // Provide a transparent image so UIKit doesn't draw a default placeholder
        self.image = Self.transparentImage
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static let transparentImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }()

    static let topMargin: CGFloat = 6
    static let bottomMargin: CGFloat = 4

    private static let headerHeight = CodyMetrics.Conversation.codeHeaderMinHeight
    private static let bottomPadding = CodySpacing.sm
    private static let maxCodeHeight = 400 - headerHeight - bottomPadding
    private var languageTitle: String { language?.lowercased() ?? "text" }

    /// Associated-object key retaining the copy-tap gesture target
    /// for the button's lifetime (see makeView).
    static var copyTapHandlerKey: UInt8 = 0

    /// Target object for the fallback tap gesture on the copy button —
    /// UITapGestureRecognizer needs an @objc target/action pair.
    final class CodeCopyTapHandler: NSObject {
        private let perform: () -> Void
        init(perform: @escaping () -> Void) { self.perform = perform }
        @objc func handleTap() { perform() }
    }

    /// [T-ios17-codeblock-copy-dead] Reference box for the double-fire guard:
    /// with both the control event AND the fallback gesture bound (see
    /// makeView), a version where the control path still works would invoke
    /// the copy twice per tap without it.
    final class CopyDebounce { var last = Date.distantPast }

    /// Cached content height from sizeThatFits, keyed by code hash + width.
    private var cachedContentHeight: (hash: Int, height: CGFloat)?

    /// Measure actual code text height using the same approach as makeView.
    private func measureCodeHeight() -> CGFloat {
        let codeHash = code.hashValue
        if let cached = cachedContentHeight, cached.hash == codeHash {
            return cached.height
        }
        let codeStyle = NSMutableParagraphStyle()
        codeStyle.lineSpacing = 4
        codeStyle.lineBreakMode = .byClipping
        let attrStr = NSAttributedString(string: code, attributes: [
            .font: theme.codeBlockFont,
            .paragraphStyle: codeStyle,
        ])
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byClipping
        tv.attributedText = attrStr
        let h = tv.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height
        cachedContentHeight = (hash: codeHash, height: h)
        return h
    }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        let width = lineFrag.width
        let scrollHeight = min(measureCodeHeight(), Self.maxCodeHeight)
        let totalHeight = Self.headerHeight + scrollHeight + Self.bottomPadding
        let height = totalHeight + Self.topMargin + Self.bottomMargin
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    /// [T-codeblock-hide-idle-scrollbars] Turn each scroll axis' indicator —
    /// and its bounce — off when that axis has nothing to scroll.
    ///
    /// The scroll view is created with both indicators and both bounces on
    /// unconditionally, so a 3-line snippet that fits entirely inside the box
    /// still showed a vertical scrollbar and rubber-banded when dragged. Most
    /// code blocks fit, so the common case was the wrong one.
    ///
    /// Compared against `scrollHeight`, NOT `bounds.height`: the frame is
    /// `scrollHeight + bottomPadding` tall with a matching `contentInset.bottom`,
    /// so the genuinely usable height is `scrollHeight`. Using the frame height
    /// would count that padding as usable space and call a block scroll-free
    /// when its last line is actually clipped.
    ///
    /// The 0.5pt tolerance absorbs sub-pixel noise from `sizeThatFits`, which
    /// otherwise leaves a scrollbar on a block that fits exactly.
    private static func syncScrollability(_ scrollView: UIScrollView,
                                          contentSize: CGSize,
                                          visibleWidth: CGFloat,
                                          scrollHeight: CGFloat) {
        let canScrollV = contentSize.height > scrollHeight + 0.5
        let canScrollH = contentSize.width > visibleWidth + 0.5
        scrollView.showsVerticalScrollIndicator = canScrollV
        scrollView.showsHorizontalScrollIndicator = canScrollH
        // Bouncing on an axis that cannot scroll reads as a glitch, and the
        // rubber-band also competes with the enclosing message list's pan.
        scrollView.alwaysBounceVertical = canScrollV
        scrollView.alwaysBounceHorizontal = canScrollH
        // When NEITHER axis can move, stop scrolling entirely rather than
        // leaving an inert scroll view in the way. Its pan recognizer would
        // still claim the touch and then do nothing with it, which is what
        // makes dragging the message list over a code block feel like it
        // catches — the list only starts moving after the finger leaves the
        // block. `isScrollEnabled = false` removes the recognizer from
        // arbitration, so the pan reaches the list immediately.
        //
        // Text selection inside the block is unaffected: that is the
        // UITextView's own long-press/selection gestures, not this pan.
        scrollView.isScrollEnabled = canScrollV || canScrollH
        // [T-codeblock-offset-reset] A reused block (codeBlockViewCache /
        // updateExistingView) can shrink to content that fits. Its old
        // scroll position would then stay applied with scrolling switched
        // off: the content shows clipped and cannot be scrolled back.
        var offset = scrollView.contentOffset
        if !canScrollH { offset.x = 0 }
        if !canScrollV { offset.y = 0 }
        if offset != scrollView.contentOffset { scrollView.contentOffset = offset }
    }

    func makeView(width: CGFloat) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = .clear

        let inset = leftInset
        let contentWidth = width - inset

        let container = CodeBlockSurface(frame: .zero)
        container.backgroundColor = theme.codeBlockBackground
        container.layer.cornerRadius = theme.codeBlockCornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        let copyWidth = CodyControlHeight.standard
        let langLabel = UILabel()
        langLabel.text = languageTitle
        langLabel.font = .systemFont(ofSize: CodySpacing.md, weight: .medium)
        langLabel.textColor = CodyUIColors.textSecondary
        langLabel.frame = CGRect(x: CodySpacing.md, y: 0,
                                 width: max(0, contentWidth - copyWidth - CodySpacing.md),
                                 height: Self.headerHeight)
        container.addSubview(langLabel)

        let divider = UIView(frame: CGRect(x: 0, y: Self.headerHeight - CodySpacing.px,
                                           width: contentWidth, height: CodySpacing.px))
        divider.backgroundColor = CodyUIColors.borderLight
        divider.isUserInteractionEnabled = false
        container.addSubview(divider)

        // Scrollable code area (own the pan gesture here for reliable horizontal scroll)
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = true
        scrollView.clipsToBounds = true
        // [T-chat-statusbar-scrolltotop-mistap] Opt OUT of the status-bar tap
        // here, so that the message list can reliably opt IN.
        //
        // This looks like the setting that was reverted on the collection view,
        // but it does the opposite job. UIKit scrolls NOTHING when more than
        // one eligible (`scrollsToTop == true`) scroll view is visible — it
        // cannot tell which one the user meant. Every rendered code block is
        // its own scroll view, so leaving this at the default would make the
        // gesture work only while no code block happened to be on screen, and
        // silently do nothing otherwise.
        //
        // Keeping it off leaves the message list as the sole candidate, which
        // is what makes "tap the status bar -> jump to the top of the chat"
        // behave the same way every time. It costs nothing: a status-bar tap is
        // never a request to scroll a code snippet.
        scrollView.scrollsToTop = false

        let codeTextView = UITextView()
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.isScrollEnabled = false // scrollView handles scrolling
        codeTextView.backgroundColor = .clear
        codeTextView.textContainerInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        codeTextView.textContainer.lineFragmentPadding = 0
        codeTextView.textContainer.lineBreakMode = .byClipping

        let codeStyle = NSMutableParagraphStyle()
        codeStyle.lineSpacing = 4
        codeStyle.lineBreakMode = .byClipping
        let codeAttr = CodySyntaxHighlighter.highlight(
            code: code,
            language: language,
            font: theme.codeBlockFont,
            paragraphStyle: codeStyle
        )
        codeTextView.attributedText = codeAttr

        // Measure content size (unconstrained width)
        let fitting = codeTextView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let contentHeight = fitting.height
        let fittingWidth = fitting.width
        codeTextView.frame = CGRect(x: 0, y: 0, width: fittingWidth, height: contentHeight)

        let scrollHeight = min(contentHeight, Self.maxCodeHeight)
        scrollView.frame = CGRect(x: 0, y: Self.headerHeight, width: contentWidth, height: scrollHeight + Self.bottomPadding)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: Self.bottomPadding, right: 0)
        scrollView.scrollIndicatorInsets = .zero
        scrollView.addSubview(codeTextView)
        scrollView.contentSize = CGSize(width: fittingWidth, height: contentHeight)
        Self.syncScrollability(scrollView,
                               contentSize: scrollView.contentSize,
                               visibleWidth: contentWidth,
                               scrollHeight: scrollHeight)

        // Auto-scroll to bottom during streaming
        let bottomY = scrollView.contentSize.height - scrollView.bounds.height
        if bottomY > 0 {
            scrollView.contentOffset = CGPoint(x: 0, y: bottomY)
        }

        container.addSubview(scrollView)

        let totalHeight = Self.headerHeight + scrollHeight + Self.bottomPadding
        container.frame = CGRect(x: inset, y: 0, width: contentWidth, height: totalHeight)

        // Copy button — 44x44 hit area per Apple HIG, icon stays small visually
        let iconConfig = UIImage.SymbolConfiguration(pointSize: CodySpacing.mdPlus, weight: .medium)
        let copyButton = UIButton(type: .system)
        copyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: iconConfig), for: .normal)
        copyButton.tintColor = CodyUIColors.iconSecondary
        copyButton.frame = CGRect(x: contentWidth - copyWidth, y: 0, width: copyWidth, height: copyWidth)
        copyButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: copyWidth - Self.headerHeight, right: 0)
        copyButton.accessibilityLabel = AppLocalized("Copy")
        let pillSize = CGSize(width: CodySpacing.xxxl, height: CodySpacing.xxl)
        let pill = UIView(frame: CGRect(x: (copyWidth - pillSize.width) / 2,
                                        y: (Self.headerHeight - pillSize.height) / 2,
                                        width: pillSize.width, height: pillSize.height))
        pill.backgroundColor = CodyUIColors.interactiveSecondaryBg
        pill.layer.cornerRadius = pillSize.height / 2
        pill.isUserInteractionEnabled = false
        copyButton.insertSubview(pill, at: 0)
        let debounce = CopyDebounce()
        let performCopy: () -> Void = { [weak codeTextView, weak copyButton] in
            // [T-ios17-codeblock-copy-dead] Double-fire guard: on versions
            // where the control event still works, a single tap now arrives
            // through BOTH the control path and the fallback gesture below.
            // The copy itself is idempotent, but guard anyway so the action
            // runs exactly once per physical tap.
            guard Date().timeIntervalSince(debounce.last) > 0.3 else { return }
            debounce.last = Date()
            // Read directly from the UITextView so we always copy the latest
            // content, even after updateExistingView replaced the attributed text.
            UIPasteboard.general.string = codeTextView?.text
            copyButton?.setImage(UIImage(systemName: "checkmark", withConfiguration: iconConfig), for: .normal)
            copyButton?.tintColor = CodyCategoryTint.green.uiColor
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copyButton?.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: iconConfig), for: .normal)
                copyButton?.tintColor = CodyUIColors.iconSecondary
            }
        }
        copyButton.addAction(UIAction { _ in performCopy() }, for: .touchUpInside)
        // [T-ios16-codeblock-copy-regression] [T-ios17-codeblock-copy-dead]
        // ALWAYS also bind an independent tap gesture on the button, on every
        // OS version. History of this line:
        //   • iOS 16: .touchUpInside stopped firing (regressed between TF26
        //     and TF28) — the host text view's gesture/interaction graph
        //     cancels the control's touches. Fallback added, gated <17 on the
        //     assumption "iOS 17+ button works".
        //   • iOS 17: field report proved that assumption wrong — same dead
        //     button. The likely toucher is visible one screen up:
        //     addInteraction(_:) DROPS UIContextMenuInteraction on iOS 16 but
        //     KEEPS it on 17+, so 17 is exactly the version where the
        //     interaction's gesture graph exists AND no fallback was bound
        //     (18+ reworked the text-interaction stack and doesn't cancel).
        // A UITapGestureRecognizer attached to the button recognizes through
        // the gesture system rather than the control-event path, so it
        // survives the cancellation on every affected version. The version
        // gate is gone for good: it encoded a per-version guess that has now
        // been wrong twice, and the debounce in performCopy makes the
        // double-bind harmless where the control path does work.
        let tapHandler = CodeCopyTapHandler(perform: performCopy)
        let tap = UITapGestureRecognizer(target: tapHandler, action: #selector(CodeCopyTapHandler.handleTap))
        tap.cancelsTouchesInView = false
        copyButton.addGestureRecognizer(tap)
        objc_setAssociatedObject(copyButton, &Self.copyTapHandlerKey, tapHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        container.addSubview(copyButton)

        container.frame.origin.y = Self.topMargin
        wrapper.addSubview(container)
        wrapper.frame = CGRect(x: 0, y: 0, width: width, height: totalHeight + Self.topMargin + Self.bottomMargin)

        return wrapper
    }

    /// Update the code text in an existing view created by `makeView(width:)` without recreating.
    func updateExistingView(_ wrapper: UIView) {
        guard let container = wrapper.subviews.first else { return }
        guard let scrollView = container.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else { return }
        guard let codeTextView = scrollView.subviews.first(where: { $0 is UITextView }) as? UITextView else { return }
        (container.subviews.first as? UILabel)?.text = languageTitle

        let codeStyle = NSMutableParagraphStyle()
        codeStyle.lineSpacing = 4
        codeStyle.lineBreakMode = .byClipping
        let codeAttr = CodySyntaxHighlighter.highlight(
            code: code,
            language: language,
            font: theme.codeBlockFont,
            paragraphStyle: codeStyle
        )
        codeTextView.attributedText = codeAttr

        let fitting = codeTextView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        codeTextView.frame.size = fitting
        scrollView.contentSize = fitting

        // Recalculate heights to match attachmentBounds logic
        let scrollHeight = min(fitting.height, Self.maxCodeHeight)
        let newScrollFrame = CGRect(x: 0, y: Self.headerHeight, width: container.frame.width,
                                    height: scrollHeight + Self.bottomPadding)
        let totalHeight = Self.headerHeight + scrollHeight + Self.bottomPadding

        // [CodeBlockGrow] Animate the visible code-frame growing taller as more
        // lines stream in, instead of snapping. The wrapper's LOGICAL height is
        // set immediately (synchronously) because the caller reads
        // `view.frame.size.height` right after this returns to lay out the
        // TextKit attachment slot + the enclosing cell — animating that would
        // desync the code frame from the text flow. Only the wrapper's visible
        // children (the rounded background container + its scroll view) animate
        // their height, so the box smoothly extends while layout stays exact.
        // [T-codeblock-hide-idle-scrollbars] Re-evaluate on every update: a block
        // that fitted a moment ago starts scrolling once streaming pushes it past
        // maxCodeHeight, and a re-render with less content goes back to fitting.
        Self.syncScrollability(scrollView,
                               contentSize: fitting,
                               visibleWidth: container.frame.width,
                               scrollHeight: scrollHeight)

        let heightGrew = totalHeight > container.frame.size.height + 0.5
        wrapper.frame.size.height = totalHeight + Self.topMargin + Self.bottomMargin
        let applyChildFrames = {
            scrollView.frame = newScrollFrame
            container.frame.size.height = totalHeight
        }
        if heightGrew && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.20,
                           delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                           animations: applyChildFrames)
        } else {
            applyChildFrames()
        }

        // Auto-scroll to bottom during streaming
        let bottomY = scrollView.contentSize.height - scrollView.bounds.height
        if bottomY > 0 {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: bottomY)
        }
    }
}

private final class CodeBlockSurface: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.borderWidth = CodySpacing.px
        if #available(iOS 17.0, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
                (view: CodeBlockSurface, _: UITraitCollection) in view.updateBorderColor()
            }
        }
        updateBorderColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorderColor()
    }

    @available(iOS, introduced: 8.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0), traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBorderColor()
        }
    }

    private func updateBorderColor() {
        layer.borderColor = CodyUIColors.borderLight.resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - Lightweight Syntax Highlighter (GitHub Light / One Dark palette)

/// Fast, bounded token highlighter using `CodySyntaxColors` (dynamic Light/Dark UIColors)
/// so fenced code blocks render full syntax coloring with zero layout overhead and instant theme updates.
private enum CodySyntaxHighlighter {
    private static let maxHighlightUTF16Length = 40_000

    private static let cache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 64
        return c
    }()

    private static let numberRegex = try! NSRegularExpression(
        pattern: #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#
    )
    private static let typeRegex = try! NSRegularExpression(
        pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#
    )
    private static let functionRegex = try! NSRegularExpression(
        pattern: #"\b([a-z_][A-Za-z0-9_]*)\s*(?=\()"#
    )
    private static let metaRegex = try! NSRegularExpression(
        pattern: #"(?:@[A-Za-z_][A-Za-z0-9_]*|^\s*#[A-Za-z_][A-Za-z0-9_]*)"#,
        options: [.anchorsMatchLines]
    )
    private static let keywordRegex = try! NSRegularExpression(
        pattern: #"\b(?:func|let|var|struct|class|enum|protocol|extension|import|return|if|else|guard|switch|case|default|for|while|repeat|break|continue|in|where|try|catch|throw|throws|async|await|actor|public|private|fileprivate|internal|open|static|final|override|mutating|weak|unowned|lazy|init|deinit|self|Self|super|nil|true|false|as|is|some|any|def|lambda|yield|pass|None|True|False|and|or|not|with|raise|except|finally|elif|from|global|nonlocal|const|function|export|new|this|typeof|instanceof|void|null|undefined|interface|type|readonly|implements|extends|package|fn|pub|mut|impl|trait|match|loop|mod|use|crate|ref|move|go|defer|chan|select|range|map|int|float|double|bool|char|auto|template|typename|namespace|using|nullptr|virtual|inline|extern|sizeof|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|DISTINCT|CASE|WHEN|THEN|ELSE|END|fi|then|elif|done|esac|local|echo)\b"#
    )
    private static let stringRegex = try! NSRegularExpression(
        pattern: #"(?:\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)"#
    )
    private static let slashCommentRegex = try! NSRegularExpression(
        pattern: #"(?://[^\n]*|/\*[\s\S]*?\*/)"#
    )
    private static let hashCommentRegex = try! NSRegularExpression(
        pattern: #"#[^\n]*"#
    )
    private static let dashCommentRegex = try! NSRegularExpression(
        pattern: #"--[^\n]*"#
    )
    private static let jsonKeyRegex = try! NSRegularExpression(
        pattern: #"\"(?:\\.|[^\"\\\n])*\"(?=\s*:)"#
    )
    private static let diffAddRegex = try! NSRegularExpression(
        pattern: #"^\+[^\n]*"#,
        options: [.anchorsMatchLines]
    )
    private static let diffDelRegex = try! NSRegularExpression(
        pattern: #"^-[^\n]*"#,
        options: [.anchorsMatchLines]
    )
    private static let diffHunkRegex = try! NSRegularExpression(
        pattern: #"^@@[^\n]*"#,
        options: [.anchorsMatchLines]
    )

    static func highlight(
        code: String,
        language: String?,
        font: UIFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let lang = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CodySyntaxColors.defaultText,
            .paragraphStyle: paragraphStyle,
        ]
        let utf16Len = code.utf16.count
        guard utf16Len > 0, utf16Len <= maxHighlightUTF16Length,
              lang != "text", lang != "txt", lang != "plain", lang != "plaintext" else {
            return NSAttributedString(string: code, attributes: baseAttrs)
        }

        let key = "\(code.hashValue):\(utf16Len):\(lang):\(Int((font.pointSize * 10).rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let result = NSMutableAttributedString(string: code, attributes: baseAttrs)
        let fullRange = NSRange(location: 0, length: utf16Len)

        if lang == "diff" || lang == "patch" {
            paint(diffAddRegex, color: CodySyntaxColors.addition, in: code, range: fullRange, target: result)
            paint(diffDelRegex, color: CodySyntaxColors.deletion, in: code, range: fullRange, target: result)
            paint(diffHunkRegex, color: CodySyntaxColors.meta, in: code, range: fullRange, target: result)
        } else if lang == "json" || lang == "jsonc" {
            paint(numberRegex, color: CodySyntaxColors.number, in: code, range: fullRange, target: result)
            paint(keywordRegex, color: CodySyntaxColors.keyword, in: code, range: fullRange, target: result)
            paint(stringRegex, color: CodySyntaxColors.string, in: code, range: fullRange, target: result)
            paint(jsonKeyRegex, color: CodySyntaxColors.attribute, in: code, range: fullRange, target: result)
            paint(slashCommentRegex, color: CodySyntaxColors.comment, in: code, range: fullRange, target: result)
        } else {
            paint(typeRegex, color: CodySyntaxColors.type, in: code, range: fullRange, target: result)
            paint(functionRegex, group: 1, color: CodySyntaxColors.function, in: code, range: fullRange, target: result)
            paint(numberRegex, color: CodySyntaxColors.number, in: code, range: fullRange, target: result)
            paint(metaRegex, color: CodySyntaxColors.meta, in: code, range: fullRange, target: result)
            paint(keywordRegex, color: CodySyntaxColors.keyword, in: code, range: fullRange, target: result)
            paint(stringRegex, color: CodySyntaxColors.string, in: code, range: fullRange, target: result)

            let usesHashComments = ["py", "python", "sh", "bash", "zsh", "shell", "yaml", "yml", "toml", "rb", "ruby", "r", "dockerfile", "makefile", "perl"].contains(lang)
            let usesDashComments = ["sql", "lua", "haskell", "hs"].contains(lang)
            if usesHashComments {
                paint(hashCommentRegex, color: CodySyntaxColors.comment, in: code, range: fullRange, target: result)
            } else if usesDashComments {
                paint(dashCommentRegex, color: CodySyntaxColors.comment, in: code, range: fullRange, target: result)
                paint(slashCommentRegex, color: CodySyntaxColors.comment, in: code, range: fullRange, target: result)
            } else {
                paint(slashCommentRegex, color: CodySyntaxColors.comment, in: code, range: fullRange, target: result)
            }
        }

        let frozen = NSAttributedString(attributedString: result)
        cache.setObject(frozen, forKey: key)
        return frozen
    }

    private static func paint(
        _ regex: NSRegularExpression,
        group: Int = 0,
        color: UIColor,
        in source: String,
        range: NSRange,
        target: NSMutableAttributedString
    ) {
        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
            guard let match, group < match.numberOfRanges else { return }
            let r = match.range(at: group)
            guard r.location != NSNotFound, r.length > 0 else { return }
            target.addAttribute(.foregroundColor, value: color, range: r)
        }
    }
}
