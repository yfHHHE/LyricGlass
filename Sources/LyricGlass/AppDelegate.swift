import AppKit
import LyricsCore
import PlaybackKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var panel: LyricsPanel!
    private var player = DesktopPlayer(rawValue: UserDefaults.standard.string(forKey: "playbackPlayer") ?? "") ?? .spotify
    private var reader: PlayerReader!
    private let lyricsProvider = LyricsProvider()
    private let readerQueue = DispatchQueue(label: "ai.yufan.lyricglass.playback", qos: .userInitiated)
    private var pollTimer: Timer?
    private var renderTimer: Timer?
    private var polling = false
    private var permissionDenied = false
    private var modeGeneration = 0
    private var lookupGeneration = 0
    private var lyricsTask: Task<Void, Never>?
    private var clock = PlaybackClock()
    private var song: Song?
    private var timeline: LyricsTimeline?
    private var imports: [String: LyricsTimeline] = [:]
    private var selectedSource: LyricsSource?
    private var message = "正在连接播放器…"
    private var secondary = "首次使用请允许读取播放器状态"
    private var source = ""
    private var demo = false
    private var demoPlaying = true
    private var demoPosition = 0.0
    private var demoSampledAt = 0.0
    private var offset = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        reader = PlayerReader(player: player)
        message = "正在连接 \(player.label)…"
        NSApp.setActivationPolicy(.accessory)
        panel = LyricsPanel()
        panel.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "LyricGlass 歌词菜单")
        statusItem.button?.toolTip = "LyricGlass · 桌面歌词"
        statusItem.menu = menu
        menu.delegate = self
        makeMenu()
        if CommandLine.arguments.contains("--demo") { startDemo() }
        pollTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        renderTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.render() }
        RunLoop.main.add(pollTimer!, forMode: .common)
        RunLoop.main.add(renderTimer!, forMode: .common)
        poll()
        render()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        renderTimer?.invalidate()
        lyricsTask?.cancel()
    }

    private func poll() {
        guard !demo, !polling, !permissionDenied else { return }
        polling = true
        let generation = modeGeneration
        let reader = self.reader!
        readerQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try reader.read() }
            DispatchQueue.main.async {
                self.polling = false
                guard !self.demo, self.modeGeneration == generation else { return }
                switch result {
                case .success(let sample): self.accept(sample)
                case .failure(let error):
                    if case PlayerReadError.changedTrack = error { return }
                    if case PlayerReadError.denied = error { self.permissionDenied = true }
                    self.clearSong()
                    self.message = "等待 \(self.player.label)"
                    self.secondary = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    private func accept(_ sample: PlaybackSample) {
        guard let track = sample.song else {
            clearSong()
            message = "\(player.label) 尚未播放歌曲"
            secondary = "播放一首歌，歌词会自动出现"
            return
        }
        clock.sample(position: sample.position, duration: track.duration, playing: sample.playing, now: sample.sampledAt)
        let changed = song?.id != track.id || song.map { abs($0.duration - track.duration) > 2 } == true
        song = track
        if changed {
            offset = 0
            lookup(track)
        }
        render()
    }

    private func clearSong() {
        if song != nil {
            lookupGeneration += 1
            lyricsTask?.cancel()
            song = nil; timeline = nil; source = ""; selectedSource = nil
        }
        clock.sample(position: 0, duration: 0, playing: false, now: now)
    }

    private func lookup(_ track: Song, force: Bool = false) {
        lookupGeneration += 1
        let generation = lookupGeneration
        lyricsTask?.cancel()
        timeline = nil
        message = "正在查找歌词…"
        secondary = "\(track.title) · \(track.artist)"
        source = "匹配中"
        selectedSource = nil
        if let imported = imports[track.id] {
            timeline = imported; source = "本地 LRC"; return
        }
        lyricsTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let record = try await self.lyricsProvider.fetch(song: track, forceReload: force)
                guard !Task.isCancelled, self.lookupGeneration == generation, self.song?.id == track.id else { return }
                self.apply(record)
            } catch {
                guard let self, !Task.isCancelled, self.lookupGeneration == generation, self.song?.id == track.id else { return }
                if case LyricsLookupError.notFound = error {
                    self.message = "暂无匹配的同步歌词"
                } else {
                    self.message = "暂时无法获取歌词"
                }
                self.secondary = error.localizedDescription
                self.source = "歌词未就绪"
            }
            self?.render()
        }
    }

    private func apply(_ record: LyricsRecord) {
        source = record.sourceLabel
        selectedSource = record.sourceKind
        if record.instrumental {
            message = "纯音乐 ♪"; secondary = "让音乐继续"; return
        }
        if record.hasSyncedLyrics, let lrc = record.syncedLyrics {
            let parsed = LyricsTimeline(lrc: lrc)
            if parsed.lines.contains(where: { !$0.text.isEmpty }) { timeline = parsed; return }
        }
        message = "这首歌暂时没有逐行时间轴"
        secondary = record.plainLyrics?.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? "可从菜单导入 LRC 歌词"
        source += " · 未同步"
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private var position: Double {
        if demo {
            let elapsed = demoPlaying ? max(0, now - demoSampledAt) : 0
            return min(40, demoPosition + elapsed)
        }
        return clock.position(at: now)
    }

    private func render() {
        guard panel != nil else { return }
        let pair = timeline?.pair(at: position + offset)
        let playing = demo ? demoPlaying : clock.isPlaying
        let info: String
        if let song {
            info = "\(demo ? "DEMO" : player.label) · \(song.artist) · \(song.title)   \(time(position)) / \(time(song.duration))   \(playing ? "播放中" : "已暂停")   \(source)   偏移 \(String(format: "%+.1fs", offset))   拖动可移动 · 右键菜单"
        } else { info = "LyricGlass · 从菜单栏选择播放器或检查自动化权限" }
        panel.lyricsView.show(current: pair?.current ?? message, next: pair?.next ?? secondary, detail: info)
        statusItem.button?.toolTip = song.map { "\($0.title) · \($0.artist)\(playing ? "" : " · 已暂停")" } ?? secondary
    }

    func menuWillOpen(_ menu: NSMenu) { if menu === self.menu { makeMenu() } }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeMenu() {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let title = NSMenuItem(title: "LyricGlass \(version) · 桌面歌词", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(NSMenuItem(title: song.map { "\($0.title) — \($0.artist)" } ?? "等待 \(player.label)", action: nil, keyEquivalent: ""))
        let playing = demo ? demoPlaying : clock.isPlaying
        menu.addItem(NSMenuItem(title: song == nil ? secondary : "\(time(position)) / \(time(song!.duration)) · \(playing ? "播放中" : "已暂停") · \(source)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let players = NSMenuItem(title: "播放器：\(player.label)", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for (index, candidate) in DesktopPlayer.allCases.enumerated() {
            let option = item(candidate.label, #selector(selectPlayer(_:)))
            option.tag = index
            option.state = candidate == player ? .on : .off
            choices.addItem(option)
        }
        players.submenu = choices
        menu.addItem(players)
        menu.addItem(item(panel.isVisible ? "隐藏歌词" : "显示歌词", #selector(toggleVisible)))
        let lock = item("锁定位置 / 鼠标穿透", #selector(toggleLock))
        lock.state = panel.ignoresMouseEvents ? .on : .off
        menu.addItem(lock)
        menu.addItem(item("恢复底部居中", #selector(recenter)))
        let font = NSMenuItem(title: "歌词字号", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for size in [24, 30, 36, 42] {
            let option = item("\(size)", #selector(changeFont(_:)))
            option.tag = size
            option.state = panel.lyricsView.fontSize == CGFloat(size) ? .on : .off
            sizes.addItem(option)
        }
        font.submenu = sizes; menu.addItem(font)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "歌词偏移 \(String(format: "%+.1fs", offset))（正数提前）", action: nil, keyEquivalent: ""))
        menu.addItem(item("歌词提前 0.5 秒", #selector(earlier)))
        menu.addItem(item("歌词延后 0.5 秒", #selector(later)))
        menu.addItem(item("重置歌词偏移", #selector(resetOffset)))
        menu.addItem(item("重新匹配歌词", #selector(retryLyrics)))
        menu.addItem(item("清空已缓存歌词", #selector(clearLyricsCache)))
        menu.addItem(item("导入当前歌曲的 LRC…", #selector(importLRC)))
        menu.addItem(.separator())
        menu.addItem(item("打开 \(player.label)", #selector(openPlayer)))
        menu.addItem(item("重试播放器连接", #selector(reconnect)))
        menu.addItem(item("打开自动化权限设置…", #selector(openPermissions)))
        let demoItem = item("演示模式（自写歌词）", #selector(toggleDemo))
        demoItem.state = demo ? .on : .off
        menu.addItem(demoItem)
        if demo {
            menu.addItem(item(demoPlaying ? "演示：暂停" : "演示：继续播放", #selector(toggleDemoPlayback)))
            menu.addItem(item("演示：跳到第 18 秒", #selector(seekDemo)))
            menu.addItem(item("演示：从头播放", #selector(restartDemo)))
        }
        menu.addItem(.separator())
        menu.addItem(item(selectedSource.map { "歌词来源：\($0.label)" } ?? "歌词来源：自动多源", #selector(openSource)))
        menu.addItem(item("退出 LyricGlass", #selector(quit), key: "q"))
    }

    @objc private func toggleVisible() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc private func toggleLock() { panel.ignoresMouseEvents.toggle(); panel.lyricsView.setHovered(false) }
    @objc private func recenter() { panel.centerAtBottom(); panel.orderFrontRegardless() }
    @objc private func changeFont(_ sender: NSMenuItem) { panel.lyricsView.fontSize = CGFloat(sender.tag) }
    @objc private func earlier() { offset = min(15, offset + 0.5); render() }
    @objc private func later() { offset = max(-15, offset - 0.5); render() }
    @objc private func resetOffset() { offset = 0; render() }
    @objc private func retryLyrics() {
        guard !demo, let song else { return }
        imports.removeValue(forKey: song.id)
        lookup(song, force: true)
    }
    @objc private func reconnect() { permissionDenied = false; poll() }
    @objc private func selectPlayer(_ sender: NSMenuItem) {
        guard DesktopPlayer.allCases.indices.contains(sender.tag) else { return }
        let selected = DesktopPlayer.allCases[sender.tag]
        guard selected != player else { return }
        modeGeneration += 1
        demo = false
        clearSong()
        player = selected
        reader = PlayerReader(player: selected)
        permissionDenied = false
        UserDefaults.standard.set(selected.rawValue, forKey: "playbackPlayer")
        message = "正在连接 \(selected.label)…"
        secondary = "首次使用请允许读取 \(selected.label) 播放状态"
        poll(); render()
    }
    @objc private func openPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else {
            NSWorkspace.shared.open(URL(string: player == .spotify ? "https://www.spotify.com/download/mac/" : "https://music.apple.com/")!); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func openPermissions() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
    @objc private func openSource() { NSWorkspace.shared.open(selectedSource?.website ?? URL(string: "https://github.com/yfHHHE/LyricGlass")!) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func clearLyricsCache() {
        lookupGeneration += 1
        lyricsTask?.cancel()
        Task { @MainActor in
            do {
                try await lyricsProvider.clearCache()
                if !demo, let song { lookup(song, force: true) }
            } catch {
                let alert = NSAlert()
                alert.messageText = "暂时无法清空歌词缓存"
                alert.informativeText = error.localizedDescription
                NSApp.activate(ignoringOtherApps: true); alert.runModal()
            }
        }
    }

    @objc private func importLRC() {
        guard let song else {
            let alert = NSAlert()
            alert.messageText = "请先在 \(player.label) 播放一首歌"
            alert.informativeText = "导入的歌词会关联当前歌曲"
            NSApp.activate(ignoringOtherApps: true); alert.runModal(); return
        }
        let picker = NSOpenPanel()
        picker.title = "为「\(song.title)」导入 LRC"
        picker.message = "选择 UTF-8 编码的 .lrc 歌词文件"
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let lrc = try String(contentsOf: url, encoding: .utf8)
            let parsed = LyricsTimeline(lrc: lrc)
            guard parsed.lines.contains(where: { !$0.text.isEmpty }) else {
                throw NSError(domain: "LyricGlass", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件中没有可用的 [分:秒] 歌词时间戳"])
            }
            lyricsTask?.cancel(); lookupGeneration += 1
            imports[song.id] = parsed
            timeline = parsed; source = "本地 LRC"; selectedSource = nil; render()
        } catch {
            let alert = NSAlert(); alert.messageText = "无法导入歌词"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }

    private func startDemo() {
        modeGeneration += 1; lookupGeneration += 1; lyricsTask?.cancel()
        demo = true; demoPlaying = true; demoPosition = 0; demoSampledAt = now; offset = 0
        song = Song(id: "demo", title: "窗边的旋律", artist: "LyricGlass 原创演示", album: "本地演示", duration: 40)
        timeline = LyricsTimeline(lrc: """
        [00:00.00]让旋律停在窗边
        [00:05.00]让文字跟着时间
        [00:10.00]切换页面，音乐继续
        [00:15.00]这一句，刚好被看见
        [00:20.00]
        [00:25.00]暂停，也等你回来
        [00:30.00]下一段，轻轻展开
        [00:35.00]桌面上的两行诗
        [00:39.00]
        """)
        source = "自写歌词 · 演示"
        selectedSource = nil
    }
    @objc private func toggleDemo() {
        if demo {
            demo = false; modeGeneration += 1; clearSong(); permissionDenied = false; poll()
        } else { startDemo() }
        render()
    }
    @objc private func toggleDemoPlayback() {
        demoPosition = position; demoSampledAt = now; demoPlaying.toggle(); render()
    }
    @objc private func seekDemo() { demoPosition = 18; demoSampledAt = now; render() }
    @objc private func restartDemo() { startDemo(); render() }

    private func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
