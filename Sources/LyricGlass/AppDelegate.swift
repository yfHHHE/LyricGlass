import AppKit
import LyricsCore
import PlaybackKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var quickMenu = QuickMenu { [weak self] action in
        guard let self else { return }
        switch action {
        case .toggleVisible: self.toggleVisible()
        case .toggleLock: self.toggleLock()
        case .settings: self.openAppearanceSettings()
        case .quit: self.quit()
        }
    }
    var menu: NSMenu { quickMenu.menu }
    private var statusItem: NSStatusItem!
    private var panel: LyricsPanel!
    private var island: IslandPanel!
    private var lyricsVisible = true
    private var screenObserver: NSObjectProtocol?
    private let appearanceStore = AppearanceStore()
    private lazy var appearance = appearanceStore.load()
    private var appearanceSettings: AppearanceSettings?
    private var lastSettingsState: SettingsPlaybackState?
    private var player = DesktopPlayer(rawValue: UserDefaults.standard.string(forKey: "playbackPlayer") ?? "") ?? .spotify
    private var mode = PlaybackMode(rawValue: UserDefaults.standard.string(forKey: "playbackMode") ?? "") ?? .automatic
    private var detectedPlayer: DesktopPlayer?
    private var monitor: PlaybackMonitor!
    private let lyricsProvider = LyricsProvider()
    private let readerQueue = DispatchQueue(label: "ai.yufan.lyricglass.playback", qos: .userInitiated)
    private var pollTimer: Timer?
    private var renderTimer: Timer?
    private var polling = false
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
    private let petAudio = PetAudioReaction()
    private var petAudioArmed = false
    private let playerController = PlayerController()
    private let commandQueue = DispatchQueue(label: "ai.yufan.lyricglass.controls", qos: .userInitiated)
    private var controlInFlight = false
    private var controlError = ""
    private var controlErrorUntil = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let selected = mode.selectedPlayer { player = selected }
        monitor = PlaybackMonitor(preferredPlayer: player)
        message = mode == .automatic ? "正在识别播放器…" : "正在连接 \(player.label)…"
        NSApp.setActivationPolicy(.accessory)
        do { try registerAppearanceFonts() }
        catch { NSLog("Could not load bundled OpenDyslexic: %@", error.localizedDescription) }
        panel = LyricsPanel()
        panel.apply(appearance)
        panel.lyricsView.onPlaybackAction = { [weak self] in self?.performSettingsAction($0) }
        island = IslandPanel()
        island.onPlaybackAction = { [weak self] in self?.performSettingsAction($0) }
        island.onSettings = { [weak self] in self?.openAppearanceSettings() }
        island.onAppearanceChange = { [weak self] in self?.setAppearance($0) }
        island.apply(appearance)
        panel.lyricsView.onContextMenu = { [weak self] event, view in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu, with: event, for: view)
        }
        updateVisibility()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.panel.centerAtBottom() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "LyricGlass")
        statusItem.button?.toolTip = "LyricGlass · 桌面歌词"
        statusItem.menu = menu
        menu.delegate = self
        makeMenu()
        makeApplicationMenu()
        if CommandLine.arguments.contains("--demo") { startDemo() }
        if CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--pet-settings") {
            openAppearanceSettings()
            if CommandLine.arguments.contains("--pet-settings") { appearanceSettings?.showPage(.pet) }
        }
        pollTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        renderTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.render() }
        RunLoop.main.add(pollTimer!, forMode: .common)
        RunLoop.main.add(renderTimer!, forMode: .common)
        poll()
        render()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        petAudio.stop()
        pollTimer?.invalidate()
        renderTimer?.invalidate()
        lyricsTask?.cancel()
        appearanceStore.defaults.synchronize()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.centerAtBottom()
        island?.reposition()
        lyricsVisible = true; updateVisibility()
        return true
    }

    private func poll() {
        guard !demo, !polling else { return }
        polling = true
        let generation = modeGeneration
        let monitor = self.monitor!
        let mode = self.mode
        readerQueue.async { [weak self] in
            guard let self else { return }
            let update = monitor.poll(mode: mode)
            DispatchQueue.main.async {
                self.polling = false
                guard !self.demo, self.modeGeneration == generation else { return }
                if let selected = update.player {
                    if self.detectedPlayer != selected { UserDefaults.standard.set(selected.rawValue, forKey: "playbackPlayer") }
                    if selected != self.player {
                        self.clearSong()
                        self.player = selected
                        self.message = "正在连接 \(selected.label)…"
                    }
                }
                self.detectedPlayer = update.player
                switch update.result {
                case .success(let sample): self.accept(sample)
                case .failure(let error):
                    if case PlayerReadError.changedTrack = error { self.render(); return }
                    self.clearSong()
                    self.message = self.detectedPlayer.map { "等待 \($0.label)" } ?? "等待播放器"
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
        secondary = record.plainLyrics?.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? "可在“播放与歌词”中导入 LRC"
        source += " · 未同步"
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private var modeLabel: String {
        mode == .automatic ? detectedPlayer.map { "自动 · \($0.label)" } ?? "自动识别" : mode.label
    }

    private var position: Double {
        if demo {
            let elapsed = demoPlaying ? max(0, now - demoSampledAt) : 0
            return min(40, demoPosition + elapsed)
        }
        return clock.position(at: now)
    }
    private var canControlPlayback: Bool { !controlInFlight && (demo || (song != nil && detectedPlayer != nil)) }

    private func render() {
        guard panel != nil else { return }
        let playbackPosition = position
        let lyricPosition = playbackPosition + offset
        let pair = timeline?.pair(at: lyricPosition)
        let context = timeline?.context(at: lyricPosition)
        let playing = demo ? demoPlaying : clock.isPlaying
        if now > controlErrorUntil { controlError = "" }
        let info: String
        if let song {
            info = "\(demo ? "DEMO" : player.label) · \(song.artist) · \(song.title)   \(time(position)) / \(time(song.duration))   \(playing ? "播放中" : "已暂停")   \(source)   偏移 \(String(format: "%+.1fs", offset))   拖动可移动 · 右键菜单"
        } else { info = "LyricGlass · 从菜单栏打开设置，连接播放器" }
        panel.lyricsView.show(current: pair?.current ?? message, next: pair?.next ?? secondary,
            detail: info + (controlError.isEmpty ? "" : " · " + controlError))
        panel.lyricsView.updatePlayback(playing: playing, enabled: canControlPlayback)
        island.islandView.show(current: pair?.current ?? message, next: pair?.next ?? secondary,
            title: song?.title ?? "LyricGlass", artist: song?.artist ?? "等待播放器", playing: playing,
            canControl: canControlPlayback, position: playbackPosition, duration: song?.duration ?? 0, error: controlError,
            context: context?.lines ?? [], currentIndex: context?.currentIndex ?? 0)
        let audioSelected = appearance.petEnabled && appearance.petMotion == .audio
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if audioSelected && petAudioArmed && playing && !demo && panel.isVisible && !reducedMotion {
            petAudio.follow(bundleID: player.bundleIdentifier, at: now)
        } else if petAudio.active { petAudio.stop() }
        let pulse = petAudio.pulse()
        panel.lyricsView.pet.update(time: now, playing: playing, motion: appearance.petMotion, pulse: pulse)
        let petStatus = reducedMotion ? "系统已开启减少动态效果，雨滴保持静止" :
            (!petAudioArmed ? "点击「连接音乐音频」后开始" : (demo ? "演示模式不采集播放器音频" : (!playing ? "已暂停 · 等待继续播放" : petAudio.status)))
        appearanceSettings?.updatePetAudioStatus(petStatus)
        statusItem.button?.toolTip = song.map { "\($0.title) · \($0.artist)\(playing ? "" : " · 已暂停")" } ?? secondary
        refreshSettingsState()
    }

    func menuWillOpen(_ menu: NSMenu) { if menu === self.menu { makeMenu() } }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeMenu() { quickMenu.update(visible: lyricsVisible, locked: panel.ignoresMouseEvents) }

    private func updateVisibility() {
        if lyricsVisible && appearance.presentation.mode.showsDesktop { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
        if lyricsVisible && appearance.presentation.mode.showsIsland { island?.orderFrontRegardless() } else { island?.orderOut(nil) }
    }
    @objc private func toggleVisible() { lyricsVisible.toggle(); updateVisibility() }
    @objc private func toggleLock() { var value = appearance; value.clickThrough.toggle(); setAppearance(value) }
    @objc private func recenter() { panel.centerAtBottom(); island.reposition(); lyricsVisible = true; updateVisibility() }
    private func setAppearance(_ value: LyricsAppearance) {
        appearance = value.normalized()
        if !appearance.petEnabled || appearance.petMotion != .audio { petAudioArmed = false; petAudio.stop() }
        appearanceStore.save(appearance)
        panel.apply(appearance)
        island.apply(appearance)
        updateVisibility()
        appearanceSettings?.update(appearance)
        render()
    }

    @objc private func openAppearanceSettings() {
        if appearanceSettings == nil {
            appearanceSettings = AppearanceSettings(style: appearance, onChange: { [weak self] in self?.setAppearance($0) },
                                                    onRecenter: { [weak self] in self?.recenter() },
                                                    onPlayer: { [weak self] in self?.selectPlaybackMode($0) },
                                                    onAction: { [weak self] in self?.performSettingsAction($0) })
        }
        refreshSettingsState(force: true)
        appearanceSettings?.showWindow()
    }

    private func refreshSettingsState(force: Bool = false) {
        guard let settings = appearanceSettings else { return }
        let playing = demo ? demoPlaying : clock.isPlaying
        let state = SettingsPlaybackState(modeIndex: PlaybackMode.allCases.firstIndex(of: mode) ?? 0,
            player: demo ? "示例歌词" : modeLabel,
            title: song?.title ?? "等待播放", artist: song?.artist ?? "在 Spotify 或 Apple Music 播放一首歌",
            status: song == nil ? secondary : "\(time(position)) / \(time(song!.duration)) · \(playing ? "播放中" : "已暂停")",
            source: source, offset: offset, hasTrack: song != nil, demo: demo, playing: playing,
            canControl: canControlPlayback, controlError: controlError)
        guard force || state != lastSettingsState else { return }
        lastSettingsState = state
        settings.updatePlayback(state)
    }

    private func performSettingsAction(_ action: SettingsAction) {
        switch action {
        case .previousTrack: controlPlayback(.previous)
        case .togglePlayback: controlPlayback(.togglePlayPause)
        case .nextTrack: controlPlayback(.next)
        case .earlier: earlier()
        case .later: later()
        case .resetOffset: resetOffset()
        case .retryLyrics: retryLyrics()
        case .importLRC: importLRC()
        case .clearCache: clearLyricsCache()
        case .reconnect: reconnect()
        case .permissions: openPermissions()
        case .openSpotify: openPlayer(.spotify)
        case .openMusic: openPlayer(.appleMusic)
        case .toggleDemo: toggleDemo()
        case .demoPlayback: toggleDemoPlayback()
        case .restartDemo: restartDemo()
        case .seekDemo: seekDemo()
        case .openSource: openSource()
        case .connectPetAudio:
            guard appearance.petEnabled && appearance.petMotion == .audio else { return }
            petAudio.retry(); petAudioArmed = true; render()
        case .openProject: NSWorkspace.shared.open(URL(string: "https://github.com/yfHHHE/LyricGlass")!)
        case .openFontLicenses:
            if let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts") { NSWorkspace.shared.open(url) }
        }
        refreshSettingsState(force: true)
    }

    private func controlPlayback(_ command: PlaybackCommand) {
        guard canControlPlayback else { return }
        controlError = ""
        if demo {
            switch command {
            case .togglePlayPause: toggleDemoPlayback()
            case .previous: restartDemo()
            case .next: seekDemo()
            }
            render(); return
        }
        guard let target = detectedPlayer else { return }
        let generation = modeGeneration
        controlInFlight = true; render()
        commandQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.playerController.perform(command, on: target) }
            DispatchQueue.main.async {
                self.controlInFlight = false
                guard self.modeGeneration == generation, self.detectedPlayer == target, !self.demo else { self.render(); return }
                if case .failure(let error) = result {
                    self.controlError = error.localizedDescription; self.controlErrorUntil = self.now + 8
                }
                self.poll(); self.render()
            }
        }
    }

    private func makeApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("设置…", #selector(openAppearanceSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("退出 LyricGlass", #selector(quit), key: "q"))
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu; main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc private func earlier() { offset = min(15, offset + 0.5); render() }
    @objc private func later() { offset = max(-15, offset - 0.5); render() }
    @objc private func resetOffset() { offset = 0; render() }
    @objc private func retryLyrics() {
        guard !demo, let song else { return }
        imports.removeValue(forKey: song.id)
        lookup(song, force: true)
    }
    @objc private func reconnect() {
        let monitor = self.monitor!
        readerQueue.async { [weak self] in
            monitor.retry()
            DispatchQueue.main.async { self?.poll() }
        }
    }
    private func selectPlaybackMode(_ index: Int) {
        guard PlaybackMode.allCases.indices.contains(index) else { return }
        let selected = PlaybackMode.allCases[index]
        guard selected != mode else { return }
        modeGeneration += 1
        demo = false
        clearSong()
        mode = selected
        detectedPlayer = nil
        if let pinned = selected.selectedPlayer { player = pinned }
        UserDefaults.standard.set(selected.rawValue, forKey: "playbackMode")
        message = selected == .automatic ? "正在识别播放器…" : "正在连接 \(selected.label)…"
        secondary = "首次使用请允许读取播放器状态"
        poll(); render()
    }
    private func openPlayer(_ player: DesktopPlayer) {
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
        song = Song(id: "demo", title: "歌词示例", artist: "演示", album: "本地示例", duration: 40)
        timeline = LyricsTimeline(lrc: PreviewLyrics.lrc)
        source = "示例歌词 · 演示"
        selectedSource = nil
    }
    @objc private func toggleDemo() {
        if demo {
            demo = false; modeGeneration += 1; clearSong(); poll()
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
