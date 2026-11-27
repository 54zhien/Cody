import Foundation

enum CodySpacing {
    static let px: CGFloat = 1
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let xsPlus: CGFloat = 6
    static let sm: CGFloat = 8
    static let smPlus: CGFloat = 10
    static let md: CGFloat = 12
    static let mdPlus: CGFloat = 14
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let s36: CGFloat = 36
    static let s40: CGFloat = 40
    static let s44: CGFloat = 44
    static let s48: CGFloat = 48
    static let s56: CGFloat = 56
    static let s64: CGFloat = 64
}

enum CodyRadius {
    static let none: CGFloat = 0
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let control: CGFloat = 12
    static let surface: CGFloat = 16
    static let bubble: CGFloat = 18
    static let composer: CGFloat = 22
    static let card: CGFloat = 24
    static let section: CGFloat = 27
    static let pill: CGFloat = 999
}

enum CodyControlHeight {
    static let sm: CGFloat = 32
    static let compact: CGFloat = 36
    static let md: CGFloat = 40
    static let standard: CGFloat = 44
    static let lg: CGFloat = 48
    static let navItem: CGFloat = 52
    static let settingsRow: CGFloat = 56
    static let settingsToggle: CGFloat = 63
    static let settingsNavMultiLine: CGFloat = 72
}

enum CodyMetrics {
    enum Sidebar {
        static let panelWidthPercent: CGFloat = 0.88
        static let panelMaxWidth: CGFloat = 380
        static let edgeWidth = CodySpacing.xxl
        static let rowMinHeight = CodyControlHeight.standard
        static let itemSpacing = CodySpacing.smPlus
        static let pinnedIconSpacing = CodySpacing.xsPlus
        static let statusIndicatorSlot = CodySpacing.lg
        static let iconSize: CGFloat = 28
        static let rowPaddingH = CodySpacing.lg
        static let sectionHeaderHeight = CodyControlHeight.sm
        static let badgeTrailingPadding = CodySpacing.sm
        static let indicatorLeadingPadding = CodySpacing.md
        static let indicatorTrailingPadding = CodySpacing.sm
    }

    enum Conversation {
        static let rowPaddingH = CodySpacing.lg
        static let liveRowMinHeight = CodyControlHeight.standard
        static let codeHeaderMinHeight = CodyControlHeight.compact
        static let paragraphSpacing = CodySpacing.xxl
        static let listItemSpacing = CodySpacing.xxs
        static let activitySpacing = CodySpacing.md
        static let activityChildSpacing = CodySpacing.sm
        static let compactGroupSpacing = CodySpacing.xxl
        static let summaryAnswerSpacing = CodySpacing.smPlus
        static let followLatestDistance: CGFloat = 50
        static let jumpToLatestDistance: CGFloat = 32
        static let loadOlderDistance: CGFloat = 240
        static let bottomFadeHeight = CodySpacing.s44
        static let topFadeExtraHeight = CodySpacing.s56
    }

    enum Composer {
        static let cornerRadius = CodyRadius.composer
        static let minHeight = CodyControlHeight.standard
        static let paddingH = CodySpacing.lg
        static let paddingV = CodySpacing.smPlus
        static let buttonVisualSize = CodySpacing.xxxl
        static let buttonHitSize = CodyControlHeight.standard
        static let buttonSpacing = CodySpacing.sm
        static let outerMarginH = CodySpacing.lg
        static let outerMarginBottom = CodySpacing.sm
    }

    enum AgentCard {
        static let padding = CodySpacing.lg
        static let gap = CodySpacing.lg
        static let cornerRadius = CodyRadius.card
        static let borderWidth: CGFloat = 0.5
        static let diffPadding = CodySpacing.md
        static let diffGap = CodySpacing.md
        static let progressHeight = CodySpacing.sm
        static let progressRadius = CodyRadius.xs
    }

    enum Settings {
        static let sectionGap: CGFloat = 22
        static let sectionRadius = CodyRadius.section
        static let rowMinHeight = CodyControlHeight.settingsRow
        static let rowPaddingV = CodySpacing.lg
        static let rowPaddingH = CodySpacing.lg
        static let toggleRowMinHeight = CodyControlHeight.settingsToggle
        static let navRowMinHeight = CodyControlHeight.settingsNavMultiLine
        static let sectionHeaderFontSize: CGFloat = 13
        static let sectionHeaderLineHeight: CGFloat = 18
        static let sectionHeaderTopSpacing = CodySpacing.xxl
        static let sectionHeaderBottomSpacing = CodySpacing.sm
        static let sectionHeaderPaddingH = CodySpacing.xxxl
        static let disclosureSize: CGFloat = 12
    }
}
