import SwiftUI
import UIKit

/// Self-drawn vector SVG icon catalog compiled into `Assets.xcassets/CodyIcons/`.
/// Every icon is stored as a template SVG with preserved vector representation so it scales
/// cleanly at any point size and inherits Light/Dark foreground tinting automatically.
enum CodyIcon: String, CaseIterable {
    case drawer = "cody_drawer"
    case home = "cody_home"
    case homeFilled = "cody_home_filled"
    case more = "cody_more"
    case moreFilled = "cody_more_filled"
    case folder = "cody_folder"
    case folderPlus = "cody_folder_plus"
    case terminal = "cody_terminal"
    case skills = "cody_skills"
    case mcp = "cody_mcp"
    case layers = "cody_layers"
    case globe = "cody_globe"
    case wrench = "cody_wrench"
    case bot = "cody_bot"
    case sparkles = "cody_sparkles"
    case sparklesFilled = "cody_sparkles_filled"
    case brain = "cody_brain"
    case cpu = "cody_cpu"
    case chart = "cody_chart"
    case alarm = "cody_alarm"
    case settings = "cody_settings"
    case sliders = "cody_sliders"
    case compose = "cody_compose"
    case search = "cody_search"
    case close = "cody_close"
    case info = "cody_info"
    case plus = "cody_plus"
    case mic = "cody_mic"
    case arrowUp = "cody_arrow_up"
    case stop = "cody_stop"
    case ellipsis = "cody_ellipsis"
    case copy = "cody_copy"
    case refresh = "cody_refresh"
    case sync = "cody_sync"
    case speaker = "cody_speaker"
    case branch = "cody_branch"
    case share = "cody_share"
    case trash = "cody_trash"
    case pin = "cody_pin"
    case cloud = "cody_cloud"
    case storage = "cody_storage"
    case moon = "cody_moon"
    case shieldCheck = "cody_shield_check"
    case doc = "cody_doc"
    case chatBubbles = "cody_chat_bubbles"
    case chevronRight = "cody_chevron_right"
    case chevronDown = "cody_chevron_down"
    case chevronUp = "cody_chevron_up"
    case waveform = "cody_waveform"
    case check = "cody_check"

    /// Maps an existing SF Symbol name to its matching self-drawn vector SVG asset, if available.
    static func fromSystemName(_ systemName: String) -> CodyIcon? {
        switch systemName {
        case "house": return .home
        case "house.fill": return .homeFilled
        case "square.grid.2x2": return .more
        case "square.grid.2x2.fill": return .moreFilled
        case "folder", "folder.fill": return .folder
        case "externaldrive.badge.plus", "folder.badge.plus": return .folderPlus
        case "terminal", "terminal.fill", "apple.terminal": return .terminal
        case "puzzlepiece.extension", "puzzlepiece.extension.fill": return .skills
        case "square.stack.3d.up", "square.stack.3d.up.fill": return .mcp
        case "square.3.layers.3d": return .layers
        case "safari", "safari.fill", "globe", "globe.americas.fill", "globe.badge.chevron.backward": return .globe
        case "wrench.and.screwdriver", "wrench.and.screwdriver.fill": return .wrench
        case "sparkles.rectangle.stack", "sparkles.rectangle.stack.fill": return .bot
        case "sparkles": return .sparkles
        case "brain.head.profile", "brain.head.profile.fill": return .brain
        case "cpu", "cpu.fill": return .cpu
        case "chart.line.uptrend.xyaxis": return .chart
        case "alarm", "alarm.fill": return .alarm
        case "gearshape", "gearshape.fill": return .settings
        case "slider.horizontal.3": return .sliders
        case "square.and.pencil": return .compose
        case "magnifyingglass": return .search
        case "xmark": return .close
        case "info.circle": return .info
        case "plus": return .plus
        case "mic", "mic.fill": return .mic
        case "arrow.up": return .arrowUp
        case "stop.fill": return .stop
        case "ellipsis": return .ellipsis
        case "doc.on.doc": return .copy
        case "arrow.clockwise": return .refresh
        case "arrow.triangle.2.circlepath", "clock.arrow.circlepath": return .sync
        case "speaker.wave.2", "speaker.wave.2.fill": return .speaker
        case "arrow.branch": return .branch
        case "square.and.arrow.up": return .share
        case "trash": return .trash
        case "pin", "pin.fill": return .pin
        case "icloud", "icloud.fill": return .cloud
        case "externaldrive", "externaldrive.fill": return .storage
        case "moon", "moon.stars": return .moon
        case "checkmark.shield", "checkmark.shield.fill": return .shieldCheck
        case "doc.text", "doc.text.fill", "doc": return .doc
        case "bubble.left.and.bubble.right", "bubble.left.fill": return .chatBubbles
        case "chevron.forward", "chevron.right": return .chevronRight
        case "chevron.down": return .chevronDown
        case "chevron.up": return .chevronUp
        case "waveform": return .waveform
        case "checkmark": return .check
        default: return nil
        }
    }

    /// Returns a template-rendered `UIImage` scaled cleanly for UIKit surfaces (menus, nav bar items).
    func uiImage(pointSize: CGFloat = 20) -> UIImage? {
        guard let raw = UIImage(named: rawValue) else { return nil }
        let target = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            raw.draw(in: CGRect(origin: .zero, size: target))
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// Renders a crisp template vector icon from `Assets.xcassets/CodyIcons/` at an exact square point size.
struct CodyIconView: View {
    private let icon: CodyIcon?
    private let fallbackSystemName: String?
    private let size: CGFloat
    private let fallbackWeight: Font.Weight

    init(_ icon: CodyIcon, size: CGFloat = 20) {
        self.icon = icon
        self.fallbackSystemName = nil
        self.size = size
        self.fallbackWeight = .regular
    }

    init(systemName: String, size: CGFloat = 20, fallbackWeight: Font.Weight = .regular) {
        self.icon = CodyIcon.fromSystemName(systemName)
        self.fallbackSystemName = systemName
        self.size = size
        self.fallbackWeight = fallbackWeight
    }

    var body: some View {
        if let icon {
            Image(icon.rawValue)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let fallbackSystemName {
            Image(systemName: fallbackSystemName)
                .font(.system(size: size * 0.92, weight: fallbackWeight))
                .frame(width: size, height: size)
        }
    }
}

/// Multicolor layered vector icon catalog compiled into `Assets.xcassets/CodyIcons/`
/// (`template-rendering-intent: original`) for Explore category cards.
enum CodyExploreIcon: String, CaseIterable {
    case files = "cody_mc_files"
    case terminal = "cody_mc_terminal"
    case skills = "cody_mc_skills"
    case mcp = "cody_mc_mcp"
    case browser = "cody_mc_browser"
    case agentTools = "cody_mc_tools"
    case subAgents = "cody_mc_agents"
    case soul = "cody_mc_soul"
    case memory = "cody_mc_memory"
    case providers = "cody_mc_providers"
    case usage = "cody_mc_usage"
    case alarms = "cody_mc_alarms"
}

/// Renders a full-color layered vector icon from `Assets.xcassets/CodyIcons/` without template tinting.
struct CodyExploreIconView: View {
    let icon: CodyExploreIcon
    let size: CGFloat

    init(_ icon: CodyExploreIcon, size: CGFloat = 34) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Colorful file-type vector icons (`Assets.xcassets/CodyIcons/cody_file_*.imageset`)
/// matching the attachment & file-browser icon taxonomy.
enum CodyFileTypeIcon: String, CaseIterable {
    case folder = "cody_mc_files"
    case pdf = "cody_file_pdf"
    case word = "cody_file_word"
    case doc = "cody_file_doc"
    case excel = "cody_file_excel"
    case sheet = "cody_file_sheet"
    case ppt = "cody_file_ppt"
    case slide = "cody_file_slide"
    case photo = "cody_file_photo"
    case code = "cody_file_code"
    case archive = "cody_file_archive"
    case audio = "cody_file_audio"
    case video = "cody_file_video"
    case generic = "cody_file_generic"

    static func forExtension(_ ext: String) -> CodyFileTypeIcon {
        switch ext.lowercased() {
        case "pdf":
            return .pdf
        case "doc", "docx":
            return .word
        case "pages", "rtf", "rtfd", "txt", "md", "markdown", "log":
            return .doc
        case "xls", "xlsx":
            return .excel
        case "csv", "tsv", "numbers":
            return .sheet
        case "ppt", "pptx":
            return .ppt
        case "key":
            return .slide
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "svg":
            return .photo
        case "swift", "py", "js", "ts", "jsx", "tsx", "c", "cpp", "cc", "h", "hpp",
             "rs", "go", "java", "kt", "rb", "php", "sh", "bash", "zsh",
             "html", "htm", "css", "scss", "sql", "json", "yaml", "yml", "toml", "xml", "plist":
            return .code
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar":
            return .archive
        case "mp3", "m4a", "wav", "aac", "ogg", "flac":
            return .audio
        case "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return .video
        default:
            return .generic
        }
    }

    static func forFileName(_ fileName: String, isDirectory: Bool = false) -> CodyFileTypeIcon {
        if isDirectory { return .folder }
        return forExtension((fileName as NSString).pathExtension)
    }
}

/// Renders a colorful file-type vector SVG at an exact point size.
struct CodyFileTypeIconView: View {
    let icon: CodyFileTypeIcon
    let size: CGFloat

    init(_ icon: CodyFileTypeIcon, size: CGFloat = 24) {
        self.icon = icon
        self.size = size
    }

    init(fileName: String, isDirectory: Bool = false, size: CGFloat = 24) {
        self.icon = CodyFileTypeIcon.forFileName(fileName, isDirectory: isDirectory)
        self.size = size
    }

    init(fileExtension: String, size: CGFloat = 24) {
        self.icon = CodyFileTypeIcon.forExtension(fileExtension)
        self.size = size
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
