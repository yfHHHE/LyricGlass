import AppKit
import CoreText

enum BackgroundMode: String, Codable, CaseIterable {
    case transparent, solid, frosted
    var label: String { ["transparent": "透明", "solid": "纯色", "frosted": "毛玻璃"][rawValue]! }
}

enum FontCategory: String, CaseIterable {
    case chineseSans = "中文 · 黑体与楷体"
    case chineseSerif = "中文 · 宋体与明体"
    case sans = "英文 · 无衬线"
    case monospace = "编程 · 等宽"
    case serif = "英文 · 衬线"
}

enum FontChoice: String, Codable, CaseIterable {
    // Preserve the original raw values so existing appearance settings keep working.
    case system, openDyslexic, rounded, serif, pingfang, mono
    case notoSans, hiragino, wenkai, notoSerif, lantingSong, youSong, genryu
    case inter, helvetica, neueHaas, jetbrains, firaCode, cascadia, sfMono, berkeley, merriweather, garamond

    var label: String {
        switch self {
        case .system: return "SF Pro / San Francisco"
        case .openDyslexic: return "OpenDyslexic"
        case .rounded: return "SF Pro Rounded"
        case .serif: return "New York"
        case .pingfang: return "苹方 / PingFang SC"
        case .mono: return "Menlo"
        case .notoSans: return "思源黑体 / Noto Sans SC"
        case .hiragino: return "冬青黑体 / Hiragino Sans GB"
        case .wenkai: return "霞鹜文楷 / LXGW WenKai"
        case .notoSerif: return "思源宋体 / Noto Serif SC"
        case .lantingSong: return "方正兰亭宋 / FZLanTingSong"
        case .youSong: return "方正悠宋 / FZYouSong"
        case .genryu: return "源流明体 / GenRyuMin"
        case .inter: return "Inter"
        case .helvetica: return "Helvetica Neue"
        case .neueHaas: return "Neue Haas Grotesk"
        case .jetbrains: return "JetBrains Mono"
        case .firaCode: return "Fira Code"
        case .cascadia: return "Cascadia Code"
        case .sfMono: return "SF Mono"
        case .berkeley: return "Berkeley Mono"
        case .merriweather: return "Merriweather"
        case .garamond: return "EB Garamond"
        }
    }
    var category: FontCategory {
        switch self {
        case .notoSans, .pingfang, .hiragino, .wenkai: return .chineseSans
        case .notoSerif, .lantingSong, .youSong, .genryu: return .chineseSerif
        case .system, .openDyslexic, .rounded, .inter, .helvetica, .neueHaas: return .sans
        case .mono, .jetbrains, .firaCode, .cascadia, .sfMono, .berkeley: return .monospace
        case .serif, .merriweather, .garamond: return .serif
        }
    }
    var isChineseFamily: Bool { category == .chineseSans || category == .chineseSerif }
    var compactLabel: String { label.components(separatedBy: " / ").first ?? label }

    var bundled: Bool {
        [.openDyslexic, .notoSans, .wenkai, .notoSerif, .genryu, .inter, .jetbrains, .firaCode, .cascadia, .merriweather, .garamond].contains(self)
    }
    var requiresLocalLicense: Bool { [.lantingSong, .youSong, .neueHaas, .berkeley].contains(self) }
    private var names: [String] {
        switch self {
        case .openDyslexic: return ["OpenDyslexic-Regular"]
        case .pingfang: return ["PingFangSC-Regular", "PingFang SC"]
        case .mono: return ["Menlo-Regular", "Menlo"]
        case .notoSans: return ["NotoSansSC-Thin_Regular", "NotoSansSC-Regular", "Noto Sans SC", "SourceHanSansSC-Regular", "Source Han Sans SC"]
        case .hiragino: return ["HiraginoSansGB-W3", "Hiragino Sans GB"]
        case .wenkai: return ["LXGWWenKai-Regular", "LXGW WenKai"]
        case .notoSerif: return ["NotoSerifSC-Regular", "Noto Serif SC", "SourceHanSerifSC-Regular", "Source Han Serif SC"]
        case .lantingSong: return ["FZLanTingSongS-R-GB", "FZLanTingSongS-R-GBK", "FZLanTingSong", "方正兰亭宋"]
        case .youSong: return ["FZYouSongS_508R", "FZYouSong", "方正悠宋"]
        case .genryu: return ["GenRyuMin2TC-R", "GenRyuMin2 TC", "GenRyuMin2TC", "GenRyuMin TC"]
        case .inter: return ["Inter-Regular", "Inter"]
        case .helvetica: return ["HelveticaNeue", "Helvetica Neue"]
        case .neueHaas: return ["NHaasGroteskTXPro-55Rg", "NHaasGroteskDSPro-55Rg", "NeueHaasGroteskTextPro", "Neue Haas Grotesk Text Pro", "Neue Haas Grotesk Display Pro", "Neue Haas Grotesk"]
        case .jetbrains: return ["JetBrainsMono-Regular", "JetBrains Mono"]
        case .firaCode: return ["FiraCode-Regular", "Fira Code"]
        case .cascadia: return ["CascadiaCode-Regular", "Cascadia Code"]
        case .berkeley: return ["BerkeleyMono-Regular", "Berkeley Mono", "Berkeley Mono Variable"]
        case .merriweather: return ["Merriweather-Regular", "Merriweather"]
        case .garamond: return ["EBGaramond-Regular", "EB Garamond"]
        default: return []
        }
    }
    private func localFont(size: CGFloat) -> NSFont? {
        for name in names { if let result = NSFont(name: name, size: size) { return result } }
        // Commercial editions can use different PostScript suffixes; accept only the same family.
        if requiresLocalLicense {
            func key(_ string: String) -> String { string.lowercased().filter { $0.isLetter || $0.isNumber } }
            let tokens = names.map(key)
            for family in NSFontManager.shared.availableFontFamilies where tokens.contains(where: { key(family).contains($0) }) {
                if let result = NSFont(name: family, size: size) { return result }
            }
        }
        return nil
    }
    var available: Bool {
        [.system, .rounded, .serif, .sfMono].contains(self) || localFont(size: 16) != nil
    }
    var availabilityLabel: String {
        if !available { return requiresLocalLicense ? "需本机授权字体" : "未安装" }
        if bundled { return "应用内置" }
        return requiresLocalLicense ? "本机字体" : "系统字体"
    }
    var note: String {
        if !available { return "当前未安装此字体，暂以系统字体显示。安装到字体册后，点刷新即可使用。" }
        if self == .openDyslexic { return "OpenDyslexic 常规与粗体已内置。" }
        if self == .wenkai { return "霞鹜文楷已内置常规与中等字重；当前句加粗时使用中等字重。" }
        if self == .genryu { return "源流明体使用繁体中文 TC 字形，常规与粗体均已内置。" }
        if category == .sans || category == .monospace || category == .serif {
            return "\(availabilityLabel)。"
        }
        return "\(availabilityLabel)，支持中文歌词。"
    }

    func font(size: CGFloat, bold: Bool) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        switch self {
        case .system: return system
        case .sfMono: return .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        case .rounded, .serif:
            let design: NSFontDescriptor.SystemDesign = self == .rounded ? .rounded : .serif
            return system.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case .openDyslexic: return NSFont(name: bold ? "OpenDyslexic-Bold" : "OpenDyslexic-Regular", size: size) ?? system
        case .wenkai: return NSFont(name: bold ? "LXGWWenKai-Medium" : "LXGWWenKai-Regular", size: size) ?? system
        case .genryu: return NSFont(name: bold ? "GenRyuMin2TC-B" : "GenRyuMin2TC-R", size: size) ?? localFont(size: size) ?? system
        default:
            guard let base = localFont(size: size) else { return system }
            return NSFontManager.shared.convert(base, toHaveTrait: bold ? .boldFontMask : .unboldFontMask)
        }
    }
}

enum LyricsDisplayMode: String, Codable, CaseIterable {
    case both, desktop, island, hidden
    var title: String {
        switch self { case .both: return "桌面歌词与灵动岛"; case .desktop: return "仅桌面歌词"; case .island: return "仅灵动岛"; case .hidden: return "全部关闭" }
    }
    init(desktop: Bool, island: Bool) {
        switch (desktop, island) {
        case (true, true): self = .both
        case (true, false): self = .desktop
        case (false, true): self = .island
        case (false, false): self = .hidden
        }
    }
    var showsDesktop: Bool { self == .both || self == .desktop }
    var showsIsland: Bool { self == .both || self == .island }
}

enum IslandShape: String, Codable, CaseIterable {
    case capsule, roundedRectangle, rectangle
    var title: String {
        switch self { case .capsule: return "胶囊"; case .roundedRectangle: return "圆角长方形"; case .rectangle: return "长方形" }
    }
    func radius(height: CGFloat, expanded: Bool) -> CGFloat {
        if expanded { return min(18, height / 2) }
        switch self { case .capsule: return height / 2; case .roundedRectangle: return min(8, height / 2); case .rectangle: return 0 }
    }
}

struct IslandAppearance: Codable, Equatable {
    // The container and clipped lyric viewport have independent widths.
    var compactWidth = 420.0
    var compactHeight = 24.0
    var expandedMaxHeight = 320.0
    var topOffset = 0.0
    var shape: IslandShape = .capsule
    private var expandedRows: Int?
    private var leftLyricWidth: Double?
    var compactLyricWidth: Double {
        get { leftLyricWidth ?? 160 }
        set { leftLyricWidth = newValue }
    }
    var expandedLineCount: Int {
        get { expandedRows == 5 ? 5 : 2 }
        set { expandedRows = newValue == 5 ? 5 : 2 }
    }
}

struct LyricsPresentation: Codable, Equatable {
    private var islandOptions: IslandAppearance?
    var islandAppearance: IslandAppearance {
        get { islandOptions ?? IslandAppearance() }
        set { islandOptions = newValue }
    }
    var mode: LyricsDisplayMode = .both
    var desktopEnabled: Bool {
        get { mode.showsDesktop }
        set { mode = LyricsDisplayMode(desktop: newValue, island: mode.showsIsland) }
    }
    var islandEnabled: Bool {
        get { mode.showsIsland }
        set { mode = LyricsDisplayMode(desktop: mode.showsDesktop, island: newValue) }
    }
    var desktopWidth = 940.0
    var islandWidth = 560.0
    var showNextLine = true
    var showControls = true
    var islandPinned = false
}

struct LyricsAppearance: Codable, Equatable {
    // Keep the old "font" storage key so existing installations retain their look.
    private var englishTypeface: FontChoice = .system
    private var chineseTypeface: FontChoice? = .pingfang
    // Optional storage lets pre-companion appearance JSON migrate without resetting it.
    private var companionVisible: Bool? = false
    private var companionMotion: PetMotion? = .gentle
    private var presentationOptions: LyricsPresentation?
    var presentation: LyricsPresentation {
        get { presentationOptions ?? LyricsPresentation() }
        set { presentationOptions = newValue }
    }
    var petEnabled: Bool {
        get { companionVisible ?? false }
        set { companionVisible = newValue }
    }
    var petMotion: PetMotion {
        get { companionMotion ?? .gentle }
        set { companionMotion = newValue }
    }
    var englishFont: FontChoice {
        get { englishTypeface }
        set { englishTypeface = newValue }
    }
    var chineseFont: FontChoice {
        get { chineseTypeface ?? (englishTypeface.isChineseFamily ? englishTypeface : .pingfang) }
        set { chineseTypeface = newValue }
    }
    init() {}
    private enum CodingKeys: String, CodingKey {
        case englishTypeface = "font", chineseTypeface = "chineseFont"
        case companionVisible, companionMotion
        case presentationOptions
        case bold, primarySize, secondarySize, primaryColor, secondaryColor, background, backgroundColor
        case opacity, cornerRadius, lineGap, padding, glassTheme, shadow, alwaysOnTop, clickThrough
    }
    var bold = true
    var primarySize = 32.0
    var secondarySize = 24.0
    var primaryColor = "FFFFFF"
    var secondaryColor = "D8DEEA"
    var background: BackgroundMode = .transparent
    var backgroundColor = "142035"
    var opacity = 0.7
    var cornerRadius = 22.0
    var lineGap = 8.0
    var padding = 22.0
    var glassTheme = 1 // system, dark, light
    var shadow = true
    var alwaysOnTop = true
    var clickThrough = false

    static func preset(_ index: Int) -> LyricsAppearance {
        var result = LyricsAppearance()
        result.background = .frosted
        if index == 0 {
            result.background = .transparent
            result.englishFont = .system
            result.primarySize = 34
        } else if index == 2 {
            result.background = .solid
            result.backgroundColor = "FFF2F6"
            result.primaryColor = "242A33"
            result.secondaryColor = "657083"
            result.opacity = 0.94
            result.cornerRadius = 16
            result.shadow = false
            result.englishFont = .rounded
        }
        return result
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
    var rgbHex: String {
        guard let color = usingColorSpace(.sRGB) else { return "FFFFFF" }
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

final class AppearanceStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> LyricsAppearance {
        guard let data = defaults.data(forKey: "appearance-v1"),
              let value = try? JSONDecoder().decode(LyricsAppearance.self, from: data) else { return LyricsAppearance() }
        return value.normalized()
    }
    func save(_ value: LyricsAppearance) { defaults.set(try? JSONEncoder().encode(value.normalized()), forKey: "appearance-v1") }
}

extension LyricsAppearance {
    func normalized() -> LyricsAppearance {
        var value = self
        var presentation = self.presentation
        presentation.desktopWidth = presentation.desktopWidth.isFinite ? min(1400, max(480, presentation.desktopWidth)) : 940
        presentation.islandWidth = presentation.islandWidth.isFinite ? min(1000, max(320, presentation.islandWidth)) : 560
        var island = presentation.islandAppearance
        island.compactWidth = island.compactWidth.isFinite ? min(1000, max(180, island.compactWidth)) : 420
        island.compactLyricWidth = island.compactLyricWidth.isFinite ? min(360, max(100, island.compactLyricWidth)) : 160
        // Restore the original capsule, including settings saved by the brief
        // two-line-as-collapsed implementation in v0.6.3.
        island.compactHeight = island.compactHeight.isFinite && island.compactHeight <= 64 ? max(18, island.compactHeight) : 24
        island.expandedMaxHeight = island.expandedMaxHeight.isFinite ? min(720, max(160, island.expandedMaxHeight)) : 320
        island.topOffset = island.topOffset.isFinite ? min(80, max(0, island.topOffset)) : 0
        presentation.islandAppearance = island
        value.presentation = presentation
        value.petEnabled = petEnabled
        value.petMotion = petMotion
        // Freeze the legacy fallback before either language is edited independently.
        value.chineseFont = chineseFont.isChineseFamily || chineseFont == .system ? chineseFont : .pingfang
        func clamp(_ number: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback
        }
        value.primarySize = clamp(primarySize, 16...64, fallback: 32)
        value.secondarySize = clamp(secondarySize, 12...48, fallback: 24)
        value.opacity = clamp(opacity, 0...1, fallback: 0.7)
        value.cornerRadius = clamp(cornerRadius, 0...36, fallback: 22)
        value.lineGap = clamp(lineGap, 0...64, fallback: 8)
        value.padding = clamp(padding, 12...48, fallback: 22)
        value.glassTheme = min(2, max(0, glassTheme))
        value.primaryColor = NSColor(hex: primaryColor)?.rgbHex ?? "FFFFFF"
        value.secondaryColor = NSColor(hex: secondaryColor)?.rgbHex ?? "D8DEEA"
        value.backgroundColor = NSColor(hex: backgroundColor)?.rgbHex ?? "142035"
        return value
    }
}

func registerAppearanceFonts() throws {
    guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
          let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
        throw NSError(domain: "LyricGlass.Fonts", code: 1)
    }
    for case let url as URL in files where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            let detail = error?.takeRetainedValue()
            if (detail as Error?)?._code == CTFontManagerError.alreadyRegistered.rawValue { continue }
            if let detail { throw detail }
            throw NSError(domain: "LyricGlass.Fonts", code: 2)
        }
    }
}
