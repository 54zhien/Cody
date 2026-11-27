import SwiftUI
import UIKit

enum CodyTypography {
    static let labelSmall: Font = .caption2
    static let labelMedium: Font = .caption.weight(.semibold)
    static let labelLarge: Font = .subheadline.weight(.semibold)
    static let bodySmall: Font = .caption
    static let bodyMedium: Font = .subheadline
    static let bodyLarge: Font = .body
    static let titleSmall: Font = .callout.weight(.medium)
    static let titleMedium: Font = .body.weight(.semibold)
    static let titleLarge: Font = .title3.weight(.semibold)
    static let headlineSmall: Font = .title2.weight(.bold)
    static let headlineMedium: Font = .title.weight(.bold)
    static let sectionHeader: Font = .footnote
    static let code = Font.system(.footnote, design: .monospaced)
}

enum CodyProseMetrics {
    static let baseBodySize: CGFloat = 17
    static let bodyLineHeight: CGFloat = 26
    static let quoteLineHeight: CGFloat = 25.65
    static let h3LineHeight: CGFloat = 21
    static let codeSize: CGFloat = 13
    static let codeLineHeight: CGFloat = 18

    @MainActor
    static func bodyFont() -> UIFont {
        .systemFont(ofSize: FontSettings.shared.scaledMessage(baseBodySize))
    }

    @MainActor
    static func codeFont() -> UIFont {
        monospacedFont(ofSize: FontSettings.shared.scaledMessage(codeSize))
    }

    @MainActor
    static func scaledLineHeight(_ lineHeight: CGFloat) -> CGFloat {
        FontSettings.shared.scaledMessage(lineHeight)
    }

    static func bodyLineHeightMultiple(for font: UIFont) -> CGFloat {
        let scaledHeight = bodyLineHeight * (font.pointSize / baseBodySize)
        return scaledHeight / font.lineHeight
    }

    static func bodyLineSpacing(for font: UIFont) -> CGFloat {
        let scaledHeight = bodyLineHeight * (font.pointSize / baseBodySize)
        return max(0, scaledHeight - font.lineHeight)
    }

    static func monospacedFont(ofSize size: CGFloat) -> UIFont {
        guard let menlo = UIFont(name: "Menlo", size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        let cjk = UIFontDescriptor(fontAttributes: [.name: "PingFang SC"])
        let descriptor = menlo.fontDescriptor.addingAttributes([.cascadeList: [cjk]])
        return UIFont(descriptor: descriptor, size: size)
    }
}
