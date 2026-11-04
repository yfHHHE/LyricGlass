import AppKit

final class PlaybackControls: NSView {
    let previous = NSButton()
    let playPause = NSButton()
    let next = NSButton()
    var onAction: ((SettingsAction) -> Void)?
    private var dark = false

    init(dark: Bool = false) {
        self.dark = dark
        super.init(frame: NSRect(x: 0, y: 0, width: 144, height: 32))
        for (button, action, symbol, title) in [
            (previous, SettingsAction.previousTrack, "backward.end.fill", "上一首"),
            (playPause, .togglePlayback, "play.fill", "播放"),
            (next, .nextTrack, "forward.end.fill", "下一首")
        ] {
            button.tag = action.rawValue
            button.target = self; button.action = #selector(choose(_:))
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.setAccessibilityLabel(title); button.toolTip = title
            button.contentTintColor = dark ? .white : .labelColor
            addSubview(button)
        }
        update(playing: false, enabled: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let size = min(36, bounds.height)
        let spacing: CGFloat = 12
        let width = size * 3 + spacing * 2
        for (index, button) in [previous, playPause, next].enumerated() {
            button.frame = NSRect(x: (bounds.width - width) / 2 + CGFloat(index) * (size + spacing),
                                  y: (bounds.height - size) / 2, width: size, height: size)
        }
    }
    func update(playing: Bool, enabled: Bool, color: NSColor? = nil) {
        let title = playing ? "暂停" : "播放"
        if playPause.toolTip != title {
            playPause.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: title)
            playPause.setAccessibilityLabel(title); playPause.toolTip = title
        }
        for button in [previous, playPause, next] {
            button.isEnabled = enabled
            button.contentTintColor = color ?? (dark ? .white : .labelColor)
        }
    }
    @objc private func choose(_ sender: NSButton) {
        if let action = SettingsAction(rawValue: sender.tag) { onAction?(action) }
    }
}
