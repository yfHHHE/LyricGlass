import AppKit

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class AppearanceSettings: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let onChange: (LyricsAppearance) -> Void
    private let onRecenter: () -> Void
    private let onPlayer: (Int) -> Void
    private let onAction: (SettingsAction) -> Void
    var style: LyricsAppearance
    let window: NSWindow
    let scene = PreviewScene(frame: .zero)
    let root = SettingsSurfaceView(frame: NSRect(x: 0, y: 0, width: 860, height: 760))
    private let content = NSView()
    private let header = NSView()
    private let headerTitle = NSTextField(labelWithString: "外观")
    private var pages: [NSScrollView] = []
    private var navigation: [SettingsSidebarButton] = []
    private(set) var selectedPage: SettingsPage = .appearance
    private let chineseFont = NSPopUpButton()
    private let englishFont = NSPopUpButton()
    private var chineseFontWidth: NSLayoutConstraint!
    private var englishFontWidth: NSLayoutConstraint!
    private let background = NSSegmentedControl(labels: BackgroundMode.allCases.map(\.label), trackingMode: .selectOne, target: nil, action: nil)
    private let theme = NSPopUpButton()
    private let glassHint = NSTextField(labelWithString: "仅毛玻璃模式可用")
    private let presets = NSSegmentedControl(labels: ["透明极简", "深色毛玻璃", "浅色卡片"], trackingMode: .selectOne, target: nil, action: nil)
    private let fontNote = NSTextField(wrappingLabelWithString: "")
    private let saved = NSTextField(labelWithString: "自动保存")
    private let bold = NSSwitch()
    private let shadow = NSSwitch()
    private let top = NSSwitch()
    private let passthrough = NSSwitch()
    private let playerMode = NSPopUpButton()
    private let trackTitle = NSTextField(labelWithString: "等待播放")
    private let trackArtist = NSTextField(labelWithString: "")
    private let playbackStatus = NSTextField(wrappingLabelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let offsetLabel = NSTextField(labelWithString: "+0.0 s")
    private let demoToggle = NSSwitch()
    private let petToggle = NSSwitch()
    private let petMotion = NSPopUpButton()
    private let petHint = NSTextField(wrappingLabelWithString: "")
    private let petAudioStatus = NSTextField(wrappingLabelWithString: "点击「连接音乐音频」后开始")
    private var petAudioSection: NSView!
    let petPreview = RaindropPetView(frame: .zero)
    private var petTimer: Timer?
    private let advancedButton = NSButton(title: "更多外观选项", target: nil, action: nil)
    private var advanced: NSView!
    private var actionButtons: [SettingsAction: NSButton] = [:]
    private var sliders: [Int: NSSlider] = [:]
    private var values: [Int: NSTextField] = [:]
    private var wells: [Int: NSColorWell] = [:]
    private var hexFields: [Int: NSTextField] = [:]
    private var previewHeight: NSLayoutConstraint!

    init(style: LyricsAppearance, onChange: @escaping (LyricsAppearance) -> Void, onRecenter: @escaping () -> Void,
         onPlayer: @escaping (Int) -> Void = { _ in }, onAction: @escaping (SettingsAction) -> Void = { _ in }) {
        self.onChange = onChange; self.onRecenter = onRecenter
        self.onPlayer = onPlayer; self.onAction = onAction
        self.style = style.normalized()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "LyricGlass · 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 780, height: 620)
        window.delegate = self
        makeUI()
        syncControls()
        apply(save: false)
        updatePlayback(SettingsPlaybackState())
        petTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.window.isVisible, self.selectedPage == .pet else { return }
            // Settings preview never starts audio recording; it demonstrates motion only.
            self.petPreview.update(time: ProcessInfo.processInfo.systemUptime, playing: true,
                                   motion: self.style.petMotion == .audio ? .gentle : self.style.petMotion)
        }
        RunLoop.main.add(petTimer!, forMode: .common)
    }
    deinit { petTimer?.invalidate() }
    func update(_ value: LyricsAppearance) { style = value.normalized(); syncControls(); apply(save: false) }
    func updatePetAudioStatus(_ text: String) {
        if petAudioStatus.stringValue != text { petAudioStatus.stringValue = text }
    }
    func windowDidBecomeKey(_ notification: Notification) { window.level = .floating }
    func windowDidResignKey(_ notification: Notification) { window.level = .normal }
    func showWindow(page: SettingsPage? = nil) {
        if let page { showPage(page) }
        if !window.isVisible, let screen = NSScreen.screens.first {
            let frame = screen.visibleFrame
            window.setContentSize(NSSize(width: min(860, frame.width - 60), height: min(780, frame.height - 80)))
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.midY - window.frame.height / 2))
        }
        let opening = !window.isVisible
        window.makeKeyAndOrderFront(nil)
        if opening { window.makeFirstResponder(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func showPage(_ page: SettingsPage) {
        selectedPage = page
        petPreview.setEnabled(page == .pet)
        headerTitle.stringValue = page.title
        for (index, view) in pages.enumerated() { view.isHidden = index != page.rawValue }
        for (index, button) in navigation.enumerated() { button.setSelected(index == page.rawValue) }
    }
    func updatePlayback(_ state: SettingsPlaybackState) {
        if playerMode.indexOfSelectedItem != state.modeIndex { playerMode.selectItem(at: state.modeIndex) }
        trackTitle.stringValue = state.title; trackArtist.stringValue = state.artist
        playbackStatus.stringValue = "\(state.player)  ·  \(state.status)"
        sourceLabel.stringValue = state.source.isEmpty ? "自动匹配" : state.source
        offsetLabel.stringValue = String(format: "%+.1f s", state.offset)
        demoToggle.state = state.demo ? .on : .off
        actionButtons[.retryLyrics]?.isEnabled = state.hasTrack && !state.demo
        actionButtons[.importLRC]?.isEnabled = state.hasTrack
        for action in [SettingsAction.earlier, .later, .resetOffset] { actionButtons[action]?.isEnabled = state.hasTrack }
        actionButtons[.demoPlayback]?.title = state.playing ? "暂停" : "继续"
        for action in [SettingsAction.demoPlayback, .restartDemo, .seekDemo] { actionButtons[action]?.isEnabled = state.demo }
    }
    private func label(_ text: String, size: CGFloat = 13, color: NSColor = SettingsPalette.text, bold: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.textColor = color
        return field
    }
    private func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 8) -> NSStackView {
        let view = NSStackView(views: views)
        view.orientation = vertical ? .vertical : .horizontal
        view.alignment = vertical ? .leading : .centerY
        view.distribution = .fill
        view.spacing = spacing
        return view
    }
    private func fullWidth(_ child: NSView, in parent: NSStackView) {
        parent.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
    }
    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
    private func row(_ name: String, _ control: NSView, height: CGFloat = 48) -> NSStackView {
        let title = label(name)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let view = stack([title, flexibleSpace(), control], spacing: 12)
        view.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
    private func section(_ title: String, rows: [NSView]) -> NSView {
        let result = stack([], vertical: true, spacing: 8)
        if !title.isEmpty {
            let heading = stack([label(title, size: 12, bold: true)], spacing: 0)
            heading.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            fullWidth(heading, in: result)
        }
        let box = SettingsGroupView()
        let contents = stack([], vertical: true, spacing: 0)
        contents.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(contents)
        NSLayoutConstraint.activate([
            contents.leadingAnchor.constraint(equalTo: box.leadingAnchor), contents.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            contents.topAnchor.constraint(equalTo: box.topAnchor), contents.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        for (index, item) in rows.enumerated() {
            if index > 0 {
                let separator = SettingsDivider()
                let line = stack([separator], spacing: 0)
                line.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                fullWidth(line, in: contents)
            }
            fullWidth(item, in: contents)
        }
        fullWidth(box, in: result)
        return result
    }
    private func slider(_ name: String, tag: Int, minimum: Double, maximum: Double) -> NSView {
        let slider = NSSlider()
        slider.minValue = minimum; slider.maxValue = maximum; slider.doubleValue = minimum
        slider.target = self; slider.action = #selector(sliderChanged(_:))
        slider.tag = tag; slider.isContinuous = true; slider.controlSize = .regular; slider.trackFillColor = SettingsPalette.accent
        slider.setAccessibilityLabel(name)
        slider.widthAnchor.constraint(equalToConstant: 176).isActive = true
        let value = NSTextField(string: "")
        value.alignment = .right; value.tag = tag; value.target = self; value.delegate = self
        value.action = #selector(numberChanged(_:)); value.setAccessibilityLabel(name + "数值")
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.isBordered = false; value.drawsBackground = false; value.textColor = SettingsPalette.text
        value.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let formatter = NumberFormatter(); formatter.minimum = NSNumber(value: minimum); formatter.maximum = NSNumber(value: maximum); formatter.maximumFractionDigits = 0
        value.formatter = formatter
        sliders[tag] = slider; values[tag] = value
        return row(name, stack([slider, value, label(tag == 2 ? "%" : "pt", size: 11, color: SettingsPalette.secondary)], spacing: 7))
    }
    private func colorTile(_ name: String, tag: Int) -> NSView {
        let well = NSColorWell()
        well.colorWellStyle = .minimal
        if #available(macOS 14.0, *) { well.supportsAlpha = false }
        well.tag = tag; well.target = self; well.action = #selector(colorChanged(_:)); well.isContinuous = true
        well.setAccessibilityLabel(name + "颜色")
        well.widthAnchor.constraint(equalToConstant: 40).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        wells[tag] = well
        let tile = stack([well, label(name, size: 10, color: SettingsPalette.secondary)], vertical: true, spacing: 4)
        tile.alignment = .centerX
        tile.widthAnchor.constraint(equalToConstant: 62).isActive = true
        let field = NSTextField(string: "")
        field.tag = tag; field.target = self; field.action = #selector(hexChanged(_:)); field.delegate = self
        field.isBordered = false; field.drawsBackground = false; field.alignment = .right; field.textColor = SettingsPalette.text
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.setAccessibilityLabel(name + "颜色十六进制色值")
        field.widthAnchor.constraint(equalToConstant: 108).isActive = true
        hexFields[tag] = field
        return tile
    }
    private func page() -> NSStackView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false
        let body = stack([], vertical: true, spacing: 22)
        body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body); scroll.documentView = document; content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22), body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        pages.append(scroll)
        return body
    }
    private func action(_ title: String, _ action: SettingsAction) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(performAction(_:)))
        button.tag = action.rawValue; SettingsNativeControls.button(button)
        actionButtons[action] = button
        return button
    }
    private func makeUI() {
        root.autoresizingMask = [.width, .height]; window.contentView = root
        root.widthAnchor.constraint(greaterThanOrEqualToConstant: 780).isActive = true
        root.heightAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        let sidebar = SettingsSidebarSurface()
        sidebar.translatesAutoresizingMaskIntoConstraints = false; content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar); root.addSubview(content)
        let line = SettingsDivider(); line.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(line)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 190),
            line.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), line.widthAnchor.constraint(equalToConstant: 1), line.topAnchor.constraint(equalTo: root.topAnchor), line.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: line.trailingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor), content.topAnchor.constraint(equalTo: root.topAnchor), content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        header.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(header)
        headerTitle.font = .systemFont(ofSize: 15, weight: .semibold); headerTitle.textColor = SettingsPalette.text
        saved.font = .systemFont(ofSize: 10); saved.textColor = SettingsPalette.muted
        let heading = stack([headerTitle, flexibleSpace(), saved]); heading.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(heading)
        let headerLine = SettingsDivider(); headerLine.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(headerLine)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor), header.trailingAnchor.constraint(equalTo: content.trailingAnchor), header.topAnchor.constraint(equalTo: content.topAnchor), header.heightAnchor.constraint(equalToConstant: 54),
            heading.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), heading.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22), heading.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerLine.leadingAnchor.constraint(equalTo: header.leadingAnchor), headerLine.trailingAnchor.constraint(equalTo: header.trailingAnchor), headerLine.bottomAnchor.constraint(equalTo: header.bottomAnchor), headerLine.heightAnchor.constraint(equalToConstant: 1)
        ])
        let brand = stack([label("LyricGlass", size: 15, bold: true), label("偏好设置", size: 11, color: SettingsPalette.secondary)], vertical: true, spacing: 8)
        brand.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(brand)
        NSLayoutConstraint.activate([brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22), brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 64)])
        let nav = stack([], vertical: true, spacing: 7); nav.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(nav)
        NSLayoutConstraint.activate([nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14), nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14), nav.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 22)])
        for page in SettingsPage.allCases {
            let button = SettingsSidebarButton(title: page.title, target: self, action: #selector(navigate(_:)))
            button.tag = page.rawValue
            button.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            button.imagePosition = .imageLeading; button.imageHugsTitle = true; button.alignment = .left; button.isBordered = false
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            fullWidth(button, in: nav); navigation.append(button)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let footer = label(version.isEmpty ? "LyricGlass" : "LyricGlass  ·  \(version)", size: 10, color: SettingsPalette.muted)
        footer.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(footer)
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18)])
        makeAppearancePage(); makePetPage(); makePlaybackPage(); makeAboutPage()
        NSColorPanel.shared.isContinuous = true; NSColorPanel.shared.showsAlpha = false
        showPage(.appearance)
    }
    private func makeAppearancePage() {
        let body = page()
        let language = NSSegmentedControl(labels: ["中英", "中文", "English"], trackingMode: .selectOne, target: self, action: #selector(languageChanged(_:)))
        language.selectedSegment = 0; SettingsNativeControls.segments(language); language.controlSize = .small
        language.widthAnchor.constraint(equalToConstant: 164).isActive = true
        let preview = stack([], vertical: true, spacing: 8)
        fullWidth(stack([label("预览", size: 11, color: SettingsPalette.secondary), flexibleSpace(), language]), in: preview)
        previewHeight = scene.heightAnchor.constraint(equalToConstant: 150); previewHeight.isActive = true
        fullWidth(scene, in: preview); fullWidth(preview, in: body)
        reloadFontMenu()
        let refresh = NSButton(title: "刷新字体", target: self, action: #selector(refreshFonts))
        SettingsNativeControls.button(refresh)
        refresh.toolTip = "安装字体后刷新"
        for (picker, name) in [(chineseFont, "中文字体"), (englishFont, "英文字体")] {
            picker.target = self; picker.action = #selector(fontChanged(_:)); SettingsNativeControls.button(picker)
            picker.alignment = .right
            picker.setAccessibilityLabel(name)
            picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        chineseFontWidth = chineseFont.widthAnchor.constraint(equalToConstant: 100)
        englishFontWidth = englishFont.widthAnchor.constraint(equalToConstant: 100)
        NSLayoutConstraint.activate([chineseFontWidth, englishFontWidth])
        presets.target = self; presets.action = #selector(presetChanged(_:)); SettingsNativeControls.segments(presets)
        presets.widthAnchor.constraint(equalToConstant: 270).isActive = true
        background.target = self; background.action = #selector(backgroundChanged(_:)); SettingsNativeControls.segments(background)
        background.widthAnchor.constraint(equalToConstant: 216).isActive = true
        theme.addItems(withTitles: ["跟随系统", "深色玻璃", "浅色玻璃"]); theme.target = self; theme.action = #selector(themeChanged(_:)); SettingsNativeControls.button(theme)
        theme.widthAnchor.constraint(equalToConstant: 200).isActive = true
        for (control, name) in [(bold, "当前句加粗"), (shadow, "文字阴影"), (top, "歌词置顶"), (passthrough, "鼠标穿透")] {
            control.target = self; control.action = #selector(togglesChanged(_:)); control.controlSize = .regular; control.setAccessibilityLabel(name)
        }
        fullWidth(section("文字", rows: [
            row("中文字体", chineseFont), row("英文字体", englishFont),
            slider("当前句字号", tag: 0, minimum: 16, maximum: 64),
            slider("下一句字号", tag: 1, minimum: 12, maximum: 48),
            row("颜色", stack([colorTile("当前句", tag: 0), colorTile("下一句", tag: 1), colorTile("背景", tag: 2)], spacing: 18), height: 68)
        ]), in: body)
        glassHint.font = .systemFont(ofSize: 12); glassHint.textColor = SettingsPalette.muted
        fullWidth(section("背景", rows: [row("预设", presets), row("背景样式", background), row("毛玻璃外观", stack([theme, glassHint])), slider("不透明度", tag: 2, minimum: 0, maximum: 100)]), in: body)
        let restore = NSButton(title: "恢复主屏位置", target: self, action: #selector(restoreDesktop)); SettingsNativeControls.button(restore)
        passthrough.toolTip = "开启后仍可从菜单栏进入设置解除"
        fullWidth(section("窗口", rows: [row("始终置顶", top), row("鼠标穿透", passthrough), row("窗口位置", restore)]), in: body)
        advancedButton.setButtonType(.onOff); advancedButton.isBordered = false; advancedButton.alignment = .left
        advancedButton.font = .systemFont(ofSize: 12); advancedButton.contentTintColor = SettingsPalette.secondary
        advancedButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        advancedButton.imagePosition = .imageLeading; advancedButton.imageHugsTitle = true
        advancedButton.target = self; advancedButton.action = #selector(toggleAdvanced(_:))
        fullWidth(advancedButton, in: body)
        let fontBook = NSButton(title: "管理本机字体…", target: self, action: #selector(openFontBook)); SettingsNativeControls.button(fontBook)
        advanced = section("", rows: [row("当前句加粗", bold), row("文字阴影", shadow),
            slider("两行间距", tag: 5, minimum: 0, maximum: 20), slider("圆角", tag: 3, minimum: 0, maximum: 36), slider("左右留白", tag: 4, minimum: 12, maximum: 48),
            row("当前句 HEX", hexFields[0]!), row("下一句 HEX", hexFields[1]!), row("背景 HEX", hexFields[2]!), row("本机字体", stack([fontBook, refresh]))])
        fullWidth(advanced, in: body); advanced.isHidden = true
        fontNote.font = .systemFont(ofSize: 11); fontNote.textColor = SettingsPalette.secondary; fontNote.maximumNumberOfLines = 3
        fullWidth(fontNote, in: body)
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults)); SettingsNativeControls.button(reset)
        fullWidth(stack([flexibleSpace(), reset]), in: body)
    }
    private func makePetPage() {
        let body = page()
        let hero = NSView()
        hero.heightAnchor.constraint(equalToConstant: 190).isActive = true
        petPreview.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(petPreview)
        petPreview.centerXAnchor.constraint(equalTo: hero.centerXAnchor).isActive = true
        petPreview.centerYAnchor.constraint(equalTo: hero.centerYAnchor).isActive = true
        petPreview.widthAnchor.constraint(equalToConstant: 180).isActive = true
        petPreview.heightAnchor.constraint(equalToConstant: 180).isActive = true
        petPreview.setEnabled(true)
        fullWidth(hero, in: body)
        petToggle.target = self; petToggle.action = #selector(petChanged(_:))
        petToggle.setAccessibilityLabel("在歌词旁显示雨滴")
        petMotion.addItems(withTitles: PetMotion.allCases.map(\.title))
        petMotion.target = self; petMotion.action = #selector(petChanged(_:))
        SettingsNativeControls.button(petMotion)
        petMotion.setAccessibilityLabel("雨滴动作")
        if #unavailable(macOS 14.2) { petMotion.item(at: 2)?.isEnabled = false }
        fullWidth(section("显示与动作", rows: [row("在歌词旁显示雨滴", petToggle), row("动作", petMotion)]), in: body)
        petAudioStatus.font = .systemFont(ofSize: 11); petAudioStatus.textColor = SettingsPalette.secondary
        petAudioStatus.maximumNumberOfLines = 2
        let connect = action("连接音乐音频", .connectPetAudio)
        petAudioSection = section("音乐律动", rows: [row("系统音频", connect), row("连接状态", petAudioStatus, height: 56)])
        fullWidth(petAudioSection, in: body)
        petHint.font = .systemFont(ofSize: 12); petHint.textColor = SettingsPalette.secondary
        petHint.maximumNumberOfLines = 6
        fullWidth(petHint, in: body)
        fullWidth(label("预览展示动作，不会申请音频权限", size: 11, color: SettingsPalette.muted), in: body)
    }
    @objc private func petChanged(_ sender: NSControl) {
        style.petEnabled = petToggle.state == .on
        style.petMotion = PetMotion.allCases[max(0, petMotion.indexOfSelectedItem)]
        syncControls(); apply()
    }
    private func makePlaybackPage() {
        let body = page()
        trackTitle.font = .systemFont(ofSize: 15, weight: .medium); trackTitle.textColor = SettingsPalette.text; trackTitle.lineBreakMode = .byTruncatingTail
        trackArtist.font = .systemFont(ofSize: 12); trackArtist.textColor = SettingsPalette.secondary
        playbackStatus.font = .systemFont(ofSize: 11); playbackStatus.textColor = SettingsPalette.secondary
        let track = stack([trackTitle, trackArtist, playbackStatus], vertical: true, spacing: 6)
        track.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        fullWidth(section("正在播放", rows: [track]), in: body)
        playerMode.addItems(withTitles: ["自动识别", "Spotify", "Apple Music"]); playerMode.target = self; playerMode.action = #selector(playerChanged(_:)); SettingsNativeControls.button(playerMode)
        playerMode.widthAnchor.constraint(equalToConstant: 180).isActive = true
        fullWidth(section("播放器", rows: [row("跟随播放器", playerMode), row("打开播放器", stack([action("Spotify", .openSpotify), action("Apple Music", .openMusic)]))]), in: body)
        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); offsetLabel.textColor = SettingsPalette.text
        sourceLabel.font = .systemFont(ofSize: 12); sourceLabel.textColor = SettingsPalette.secondary; sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
        fullWidth(section("歌词", rows: [
            row("同步偏移", stack([offsetLabel, action("− 0.5", .later), action("归零", .resetOffset), action("+ 0.5", .earlier)], spacing: 6)),
            row("当前来源", stack([sourceLabel, action("查看", .openSource)])),
            row("歌词文件", stack([action("重新匹配", .retryLyrics), action("导入 LRC…", .importLRC)]))
        ]), in: body)
        fullWidth(section("连接与缓存", rows: [row("连接", stack([action("重试连接", .reconnect), action("自动化权限…", .permissions)])), row("本地缓存", action("清空歌词缓存", .clearCache))]), in: body)
        demoToggle.target = self; demoToggle.tag = SettingsAction.toggleDemo.rawValue; demoToggle.action = #selector(performAction(_:)); demoToggle.controlSize = .regular; demoToggle.setAccessibilityLabel("使用示例歌词")
        fullWidth(section("演示", rows: [row("使用示例歌词", demoToggle), row("演示控制", stack([action("暂停", .demoPlayback), action("从头播放", .restartDemo), action("跳到 18 秒", .seekDemo)]))]), in: body)
    }
    private func makeAboutPage() {
        let body = page()
        let brand = stack([label("LyricGlass", size: 24, bold: true), label("Spotify 与 Apple Music 的桌面歌词", size: 12, color: SettingsPalette.secondary)], vertical: true, spacing: 8)
        fullWidth(brand, in: body)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "本机版"
        fullWidth(section("", rows: [row("版本", label(version, size: 12, color: SettingsPalette.secondary)), row("项目", action("打开 GitHub", .openProject)), row("字体", action("查看字体许可", .openFontLicenses))]), in: body)
        let note = NSTextField(wrappingLabelWithString: "开放字体随应用提供。Apple 字体使用系统版本；方正、Neue Haas 和 Berkeley 使用本机已安装的授权字体。")
        note.font = .systemFont(ofSize: 11); note.textColor = SettingsPalette.secondary
        fullWidth(note, in: body)
    }
    @objc private func toggleAdvanced(_ sender: NSButton) {
        advanced.isHidden = sender.state != .on
        sender.image = NSImage(systemSymbolName: sender.state == .on ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
    }
    private func reloadFontMenu() {
        for (picker, chineseOnly) in [(chineseFont, true), (englishFont, false)] {
            let menu = NSMenu(); menu.autoenablesItems = false
            for category in FontCategory.allCases {
                var choices = FontChoice.allCases.filter { $0.category == category && (!chineseOnly || $0.isChineseFamily) }
                if chineseOnly && category == .chineseSans { choices.insert(.system, at: 0) }
                guard !choices.isEmpty else { continue }
                if !menu.items.isEmpty { let separator = NSMenuItem.separator(); separator.tag = -1; menu.addItem(separator) }
                let heading = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
                heading.isEnabled = false; heading.tag = -1
                heading.attributedTitle = NSAttributedString(string: category.rawValue, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: SettingsPalette.secondary])
                menu.addItem(heading)
                for choice in choices {
                    let name = chineseOnly && choice == .system ? "系统中文" : choice.compactLabel
                    let item = NSMenuItem(title: name + (choice.available ? "" : " · 未安装"), action: nil, keyEquivalent: "")
                    item.tag = FontChoice.allCases.firstIndex(of: choice)!
                    item.isEnabled = choice.available
                    item.toolTip = "\(choice.label) · \(choice.availabilityLabel)"
                    item.indentationLevel = 1
                    menu.addItem(item)
                }
            }
            picker.menu = menu
            let choice = chineseOnly ? style.chineseFont : style.englishFont
            picker.selectItem(withTag: FontChoice.allCases.firstIndex(of: choice)!)
        }
    }
    private func syncFont(_ picker: NSPopUpButton, choice: FontChoice, width: NSLayoutConstraint) {
        picker.selectItem(withTag: FontChoice.allCases.firstIndex(of: choice)!)
        let text = picker.selectedItem?.title ?? choice.compactLabel
        let measured = (text as NSString).size(withAttributes: [.font: picker.font ?? NSFont.systemFont(ofSize: 13)]).width
        width.constant = min(230, max(80, ceil(measured) + 38))
        picker.toolTip = choice.label
    }
    private func syncControls() {
        petToggle.state = style.petEnabled ? .on : .off
        petMotion.selectItem(at: PetMotion.allCases.firstIndex(of: style.petMotion) ?? 1)
        petMotion.isEnabled = style.petEnabled
        petAudioSection.isHidden = style.petMotion != .audio
        actionButtons[.connectPetAudio]?.isEnabled = style.petEnabled && style.petMotion == .audio
        if #unavailable(macOS 14.2) { actionButtons[.connectPetAudio]?.isEnabled = false }
        switch style.petMotion {
        case .still: petHint.stringValue = "保持静止，偶尔眨眼。开启系统「减少动态效果」后会停止眨眼。"
        case .gentle: petHint.stringValue = "播放时循环摇摆，暂停时停止，不分析音乐节拍。"
        case .audio: petHint.stringValue = "根据正在播放的音乐强弱弹跳，需要 macOS 14.2 或更新版本与系统音频录制权限。只分析即时强弱，不保存或上传音频；不使用麦克风。"
        }
        syncFont(chineseFont, choice: style.chineseFont, width: chineseFontWidth)
        syncFont(englishFont, choice: style.englishFont, width: englishFontWidth)
        background.selectedSegment = BackgroundMode.allCases.firstIndex(of: style.background)!
        theme.selectItem(at: style.glassTheme)
        let numbers = [style.primarySize, style.secondarySize, style.opacity * 100, style.cornerRadius, style.padding, style.lineGap]
        for (tag, number) in numbers.enumerated() { sliders[tag]?.doubleValue = number; values[tag]?.doubleValue = number }
        for (tag, hex) in [style.primaryColor, style.secondaryColor, style.backgroundColor].enumerated() {
            wells[tag]?.color = NSColor(hex: hex) ?? .white; hexFields[tag]?.stringValue = "#" + hex
        }
        bold.state = style.bold ? .on : .off; shadow.state = style.shadow ? .on : .off
        top.state = style.alwaysOnTop ? .on : .off; passthrough.state = style.clickThrough ? .on : .off
        let hasBackground = style.background != .transparent
        wells[2]?.isEnabled = hasBackground; hexFields[2]?.isEnabled = hasBackground
        sliders[2]?.isEnabled = hasBackground; values[2]?.isEnabled = hasBackground
        theme.isEnabled = style.background == .frosted
        theme.isHidden = style.background != .frosted
        glassHint.isHidden = style.background == .frosted
        fontNote.stringValue = "中文：\(style.chineseFont.note)\n英文：\(style.englishFont.note) 数字和半角标点跟随英文字体。"
    }
    private func apply(save: Bool = true) {
        var visualStyle = style
        visualStyle.petEnabled = false; visualStyle.petMotion = .gentle
        presets.selectedSegment = (0...2).first { LyricsAppearance.preset($0) == visualStyle } ?? -1
        scene.lyrics.apply(style)
        previewHeight.constant = scene.lyrics.preferredPreviewHeight
        if save { onChange(style); saved.stringValue = "已自动保存" }
    }
    @objc private func navigate(_ sender: NSButton) { if let page = SettingsPage(rawValue: sender.tag) { showPage(page) } }
    @objc private func playerChanged(_ sender: NSPopUpButton) { onPlayer(sender.indexOfSelectedItem) }
    @objc private func performAction(_ sender: NSControl) { if let action = SettingsAction(rawValue: sender.tag) { onAction(action) } }
    @objc private func refreshFonts() { reloadFontMenu(); syncControls() }
    @objc private func openFontBook() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FontBook") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func sliderChanged(_ sender: NSSlider) {
        sender.doubleValue = sender.doubleValue.rounded()
        values[sender.tag]?.doubleValue = sender.doubleValue
        setNumber(tag: sender.tag, number: sender.doubleValue)
    }
    @objc private func numberChanged(_ sender: NSTextField) {
        guard let slider = sliders[sender.tag] else { return }
        let number = min(slider.maxValue, max(slider.minValue, sender.doubleValue)).rounded()
        sender.doubleValue = number; slider.doubleValue = number
        setNumber(tag: sender.tag, number: number)
    }
    private func setNumber(tag: Int, number: Double) {
        switch tag {
        case 0: style.primarySize = number
        case 1: style.secondarySize = number
        case 2: style.opacity = number / 100
        case 3: style.cornerRadius = number
        case 4: style.padding = number
        case 5: style.lineGap = number
        default: return
        }
        apply()
    }
    @objc private func colorChanged(_ sender: NSColorWell) { setColor(tag: sender.tag, hex: sender.color.rgbHex) }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if values[field.tag] === field, let slider = sliders[field.tag],
           let number = Double(field.stringValue), number.isFinite, (slider.minValue...slider.maxValue).contains(number) {
            slider.doubleValue = number.rounded()
            setNumber(tag: field.tag, number: number.rounded())
        } else if hexFields[field.tag] === field, let color = NSColor(hex: field.stringValue) {
            setColor(tag: field.tag, hex: color.rgbHex)
        }
    }
    @objc private func hexChanged(_ sender: NSTextField) {
        guard let color = NSColor(hex: sender.stringValue) else { NSSound.beep(); syncControls(); return }
        setColor(tag: sender.tag, hex: color.rgbHex)
    }
    private func setColor(tag: Int, hex: String) {
        if tag == 0 { style.primaryColor = hex } else if tag == 1 { style.secondaryColor = hex } else { style.backgroundColor = hex }
        wells[tag]?.color = NSColor(hex: hex)!
        hexFields[tag]?.stringValue = "#" + hex
        apply()
    }
    @objc private func fontChanged(_ sender: NSPopUpButton) {
        guard FontChoice.allCases.indices.contains(sender.selectedTag()) else { return }
        let choice = FontChoice.allCases[sender.selectedTag()]
        if sender === chineseFont { style.chineseFont = choice } else { style.englishFont = choice }
        syncControls(); apply()
    }
    @objc private func backgroundChanged(_ sender: NSSegmentedControl) { style.background = BackgroundMode.allCases[sender.selectedSegment]; syncControls(); apply() }
    @objc private func themeChanged(_ sender: NSPopUpButton) { style.glassTheme = sender.indexOfSelectedItem; apply() }
    @objc private func togglesChanged(_ sender: NSControl) {
        style.bold = bold.state == .on; style.shadow = shadow.state == .on
        style.alwaysOnTop = top.state == .on; style.clickThrough = passthrough.state == .on
        apply()
    }
    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        scene.setLanguage(sender.selectedSegment)
    }
    @objc private func presetChanged(_ sender: NSSegmentedControl) {
        guard (0...2).contains(sender.selectedSegment) else { return }
        let enabled = style.petEnabled, motion = style.petMotion
        style = .preset(sender.selectedSegment); style.petEnabled = enabled; style.petMotion = motion
        syncControls(); apply()
    }
    @objc private func resetDefaults() { style = LyricsAppearance(); syncControls(); apply() }
    @objc private func restoreDesktop() { onRecenter() }
}
