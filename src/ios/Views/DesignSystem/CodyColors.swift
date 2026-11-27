import SwiftUI
import UIKit

enum CodyUIColors {
    static func dynamic(
        light: UInt32,
        lightAlpha: CGFloat = 1,
        dark: UInt32,
        darkAlpha: CGFloat = 1
    ) -> UIColor {
        let lightColor = rgb(light, alpha: lightAlpha)
        let darkColor = rgb(dark, alpha: darkAlpha)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        }
    }

    private static func rgb(_ value: UInt32, alpha: CGFloat) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    // MARK: - Surfaces

    static let bgCanvas = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let bgCanvasSubtle = dynamic(light: 0xFCFCFC, dark: 0x000000)
    static let bgPrimary = dynamic(light: 0xFFFFFF, dark: 0x212121)
    static let bgSecondary = dynamic(light: 0xE8E8E8, dark: 0x303030)
    static let bgTertiary = dynamic(light: 0xF3F3F3, dark: 0x414141)
    static let bgElevatedPrimary = dynamic(light: 0xFFFFFF, dark: 0x303030)
    static let bgElevatedSecondary = dynamic(light: 0xF3F3F3, dark: 0x212121)
    static let bgGrouped = dynamic(light: 0xF2F2F7, dark: 0x000000)
    static let bgGroupedSurface = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let bgSystemElevated = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let bgListIcon = dynamic(light: 0xF9F9F9, dark: 0x181818)
    static let bgUserBubble = dynamic(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.13)
    static let bgCodeBlock = dynamic(light: 0xF8F8F8, dark: 0x212121)
    static let bgInlineCode = dynamic(light: 0xF2F2F7, dark: 0x3A3A3C)
    static let bgScrim = dynamic(light: 0xE3E3E3, lightAlpha: 0.50, dark: 0x0D0D0D, darkAlpha: 0.50)
    static let bgProgressTrack = dynamic(light: 0x339CFF, lightAlpha: 0.18, dark: 0x339CFF, darkAlpha: 0.18)

    // MARK: - Borders and separators

    static let borderLight = dynamic(light: 0x0D0D0D, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.05)
    static let borderDefault = dynamic(light: 0x0D0D0D, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.15)
    static let borderHeavy = dynamic(light: 0x0D0D0D, lightAlpha: 0.15, dark: 0xFFFFFF, darkAlpha: 0.20)
    static let borderInput = dynamic(light: 0xEBEBEB, dark: 0xFFFFFF, darkAlpha: 0.15)
    static let borderListIcon = dynamic(light: 0x0D0D0D, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let separator = dynamic(light: 0xE8E8E8, dark: 0x38383B)

    // MARK: - Text and icons

    static let textPrimary = dynamic(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x5D5D5D, dark: 0xCDCDCD)
    static let textTertiary = dynamic(light: 0x8F8F8F, dark: 0xAFAFAF)
    static let textInverse = dynamic(light: 0xFFFFFF, dark: 0x0D0D0D)
    static let textAccent = dynamic(light: 0x0285FF, dark: 0x48AAFF)
    static let textLink = dynamic(light: 0x0285FF, dark: 0x48AAFF)
    static let iconPrimary = dynamic(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let iconSecondary = dynamic(light: 0x5D5D5D, dark: 0xCDCDCD)
    static let iconTertiary = dynamic(light: 0x8F8F8F, dark: 0xAFAFAF)
    static let iconAccent = dynamic(light: 0x0285FF, dark: 0x48AAFF)
    static let iconDisclosure = dynamic(light: 0x8A8A8E, dark: 0x9F9FA5)

    // MARK: - Interactive

    static let interactivePrimaryBg = dynamic(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let interactivePrimaryLabel = dynamic(light: 0xFFFFFF, dark: 0x0D0D0D)
    static let interactiveSecondaryBg = dynamic(light: 0xF3F3F3, dark: 0x303030)
    static let interactiveRowPress = dynamic(light: 0xF9F9F9, dark: 0x181818)
    static let interactiveControlDefault = dynamic(light: 0xCDCDCD, dark: 0x414141)
    static let interactiveProgressFill = dynamic(light: 0x339CFF, dark: 0x48AAFF)

    // MARK: - Status

    static let statusErrorBg = dynamic(light: 0xFFF0F0, dark: 0x4D100E)
    static let statusErrorText = dynamic(light: 0xFF002A, dark: 0xFF8583)
    static let statusSuccessBg = dynamic(light: 0xD9F4E4, dark: 0x004F1F)
    static let statusSuccessText = dynamic(light: 0x004F1F, dark: 0xEDFAF2)
    static let statusWarningBg = dynamic(light: 0xFFF5F0, dark: 0x4A2206)
    static let statusWarningText = dynamic(light: 0xE25507, dark: 0xFF9E6C)
    static let connectionReady = dynamic(light: 0x1AC27D, dark: 0x1AC27D)
    static let streamingHighlight = dynamic(light: 0x3A83F7, dark: 0x48AAFF)
    static let thinkingNeutral = dynamic(light: 0x8F8F8F, dark: 0xAFAFAF)

    // MARK: - Loading

    static let loadingBg = dynamic(light: 0xEFEFF0, dark: 0x303030)
    static let loadingFg = dynamic(light: 0xFFFFFF, dark: 0x424242)

    static let syntaxDefault = CodySyntaxColors.defaultText
}

enum CodyColors {
    // MARK: - Surfaces

    static let bgCanvas = Color(uiColor: CodyUIColors.bgCanvas)
    static let bgCanvasSubtle = Color(uiColor: CodyUIColors.bgCanvasSubtle)
    static let bgPrimary = Color(uiColor: CodyUIColors.bgPrimary)
    static let bgSecondary = Color(uiColor: CodyUIColors.bgSecondary)
    static let bgTertiary = Color(uiColor: CodyUIColors.bgTertiary)
    static let bgElevatedPrimary = Color(uiColor: CodyUIColors.bgElevatedPrimary)
    static let bgElevatedSecondary = Color(uiColor: CodyUIColors.bgElevatedSecondary)
    static let bgGrouped = Color(uiColor: CodyUIColors.bgGrouped)
    static let bgGroupedSurface = Color(uiColor: CodyUIColors.bgGroupedSurface)
    static let bgSystemElevated = Color(uiColor: CodyUIColors.bgSystemElevated)
    static let bgListIcon = Color(uiColor: CodyUIColors.bgListIcon)
    static let bgUserBubble = Color(uiColor: CodyUIColors.bgUserBubble)
    static let bgCodeBlock = Color(uiColor: CodyUIColors.bgCodeBlock)
    static let bgInlineCode = Color(uiColor: CodyUIColors.bgInlineCode)
    static let bgScrim = Color(uiColor: CodyUIColors.bgScrim)
    static let bgProgressTrack = Color(uiColor: CodyUIColors.bgProgressTrack)

    // MARK: - Borders and separators

    static let borderLight = Color(uiColor: CodyUIColors.borderLight)
    static let borderDefault = Color(uiColor: CodyUIColors.borderDefault)
    static let borderHeavy = Color(uiColor: CodyUIColors.borderHeavy)
    static let borderInput = Color(uiColor: CodyUIColors.borderInput)
    static let borderListIcon = Color(uiColor: CodyUIColors.borderListIcon)
    static let separator = Color(uiColor: CodyUIColors.separator)

    // MARK: - Text and icons

    static let textPrimary = Color(uiColor: CodyUIColors.textPrimary)
    static let textSecondary = Color(uiColor: CodyUIColors.textSecondary)
    static let textTertiary = Color(uiColor: CodyUIColors.textTertiary)
    static let textInverse = Color(uiColor: CodyUIColors.textInverse)
    static let textAccent = Color(uiColor: CodyUIColors.textAccent)
    static let textLink = Color(uiColor: CodyUIColors.textLink)
    static let iconPrimary = Color(uiColor: CodyUIColors.iconPrimary)
    static let iconSecondary = Color(uiColor: CodyUIColors.iconSecondary)
    static let iconTertiary = Color(uiColor: CodyUIColors.iconTertiary)
    static let iconAccent = Color(uiColor: CodyUIColors.iconAccent)
    static let iconDisclosure = Color(uiColor: CodyUIColors.iconDisclosure)

    // MARK: - Interactive

    static let interactivePrimaryBg = Color(uiColor: CodyUIColors.interactivePrimaryBg)
    static let interactivePrimaryLabel = Color(uiColor: CodyUIColors.interactivePrimaryLabel)
    static let interactiveSecondaryBg = Color(uiColor: CodyUIColors.interactiveSecondaryBg)
    static let interactiveRowPress = Color(uiColor: CodyUIColors.interactiveRowPress)
    static let interactiveControlDefault = Color(uiColor: CodyUIColors.interactiveControlDefault)
    static let interactiveProgressFill = Color(uiColor: CodyUIColors.interactiveProgressFill)

    // MARK: - Status

    static let statusErrorBg = Color(uiColor: CodyUIColors.statusErrorBg)
    static let statusErrorText = Color(uiColor: CodyUIColors.statusErrorText)
    static let statusSuccessBg = Color(uiColor: CodyUIColors.statusSuccessBg)
    static let statusSuccessText = Color(uiColor: CodyUIColors.statusSuccessText)
    static let statusWarningBg = Color(uiColor: CodyUIColors.statusWarningBg)
    static let statusWarningText = Color(uiColor: CodyUIColors.statusWarningText)
    static let connectionReady = Color(uiColor: CodyUIColors.connectionReady)
    static let streamingHighlight = Color(uiColor: CodyUIColors.streamingHighlight)
    static let thinkingNeutral = Color(uiColor: CodyUIColors.thinkingNeutral)

    // MARK: - Loading

    static let loadingBg = Color(uiColor: CodyUIColors.loadingBg)
    static let loadingFg = Color(uiColor: CodyUIColors.loadingFg)

    static let syntaxDefault = Color(uiColor: CodyUIColors.syntaxDefault)
}

enum CodySyntaxColors {
    static let defaultText = CodyUIColors.dynamic(light: 0x000000, dark: 0xABB2BF)
    static let keyword = CodyUIColors.dynamic(light: 0xAA0D91, dark: 0xC678DD)
    static let string = CodyUIColors.dynamic(light: 0xC41A16, dark: 0x98C379)
    static let comment = CodyUIColors.dynamic(light: 0x007400, dark: 0x5C6370)
    static let number = CodyUIColors.dynamic(light: 0x1C00CF, dark: 0xD19A66)
    static let type = CodyUIColors.dynamic(light: 0x5C2699, dark: 0xE6C07B)
    static let function = CodyUIColors.dynamic(light: 0x1C00CF, dark: 0x61AEEE)
    static let variable = CodyUIColors.dynamic(light: 0x3F6E74, dark: 0xD19A66)
    static let attribute = CodyUIColors.dynamic(light: 0xAA0D91, dark: 0x98C379)
    static let addition = CodyUIColors.dynamic(light: 0x268A1F, dark: 0x98C379)
    static let deletion = CodyUIColors.dynamic(light: 0xD73A49, dark: 0xE06C75)
    static let meta = CodyUIColors.dynamic(light: 0x9B2393, dark: 0x61AEEE)
}

/// Muted foreground tints for session and tool symbols.
enum CodyCategoryTint {
    case neutral, blue, green, orange, purple, red

    var color: Color { Color(uiColor: uiColor) }

    var uiColor: UIColor {
        switch self {
        case .neutral: CodyUIColors.iconSecondary
        case .blue: Self.mutedBlue
        case .green: Self.mutedGreen
        case .orange: Self.mutedOrange
        case .purple: Self.mutedPurple
        case .red: Self.mutedRed
        }
    }

    private static let mutedBlue = CodyUIColors.dynamic(light: 0x425E78, dark: 0x9AB6CF)
    private static let mutedGreen = CodyUIColors.dynamic(light: 0x456557, dark: 0x9CBDAA)
    private static let mutedOrange = CodyUIColors.dynamic(light: 0x79573B, dark: 0xCDAE91)
    private static let mutedPurple = CodyUIColors.dynamic(light: 0x655479, dark: 0xB7A8CB)
    private static let mutedRed = CodyUIColors.dynamic(light: 0x7D5057, dark: 0xCEA4A9)
}
