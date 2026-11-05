import Foundation

enum SettingsPage: Int, CaseIterable {
    case desktop, island, typography, pet, playback, about
    var title: String { ["桌面悬浮", "灵动岛", "文字与字体", "雨滴", "播放与歌词", "关于"][rawValue] }
    var symbol: String { ["rectangle.on.rectangle", "capsule", "textformat", "drop", "waveform", "info.circle"][rawValue] }
}

enum SettingsAction: Int, CaseIterable {
    case earlier, later, resetOffset, retryLyrics, importLRC, clearCache, reconnect, permissions
    case openSpotify, openMusic, toggleDemo, demoPlayback, restartDemo, seekDemo, openSource, openProject, openFontLicenses
    case connectPetAudio
    case previousTrack, togglePlayback, nextTrack
}

struct SettingsPlaybackState: Equatable {
    var modeIndex = 0
    var player = "自动识别"
    var title = "等待播放"
    var artist = "在 Spotify 或 Apple Music 播放一首歌"
    var status = "尚未连接播放器"
    var source = "自动匹配同步歌词"
    var offset = 0.0
    var hasTrack = false
    var demo = false
    var playing = false
    var canControl = false
    var controlError = ""
}
