import AppKit
import QuartzCore

struct IslandGeometry {
    var screenFrame: NSRect
    var topInset: CGFloat
    var notchWidth: CGFloat
    var topOffset: CGFloat = 0

    init(screenFrame: NSRect, topInset: CGFloat = 0, notchWidth: CGFloat = 0) {
        self.screenFrame = screenFrame; self.topInset = topInset; self.notchWidth = notchWidth
    }
    init(screen: NSScreen) {
        screenFrame = screen.frame
        topInset = screen.safeAreaInsets.top
        if topInset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 0 }
    }
    var hasNotch: Bool { topInset > topOffset }
    var contentTopInset: CGFloat { hasNotch ? topInset - topOffset + 8 : 8 }
    func frame(expanded: Bool, width: CGFloat, height: CGFloat, compactWidth: CGFloat = 420, compactHeight: CGFloat = 24) -> NSRect {
        let desiredWidth = max(expanded ? max(width, compactWidth) : compactWidth, hasNotch ? notchWidth + 100 : 0)
        let actualWidth = min(desiredWidth, max(1, screenFrame.width - 24))
        let actualHeight = min(expanded ? height : max(compactHeight, hasNotch ? topInset - topOffset + 4 : 0), max(1, screenFrame.height - topOffset - 12))
        return NSRect(x: screenFrame.midX - actualWidth / 2, y: screenFrame.maxY - topOffset - actualHeight,
                      width: actualWidth, height: actualHeight)
    }
}

final class IslandPanel: NSPanel {
    let islandView = IslandView()
    private(set) var expanded = false
    private var style = LyricsAppearance()
    private var collapse: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    var onAppearanceChange: ((LyricsAppearance) -> Void)?
    var onSettings: (() -> Void)? {
        didSet { islandView.onSettings = onSettings }
    }
    var onPlaybackAction: ((SettingsAction) -> Void)? {
        didSet { islandView.controls.onAction = onPlaybackAction }
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 32),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "LyricGlass · 灵动岛"
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        contentView = islandView
        islandView.onPreferredHeightChange = { [weak self] in
            guard let self else { return }
            self.resizeToFitContent()
        }
        islandView.onHover = { [weak self] hovered in
            guard let self else { return }
            self.collapse?.cancel()
            if hovered { self.setExpanded(true) }
            else { self.scheduleCollapse() }
        }
        islandView.onExpand = { [weak self] in
            guard let self else { return }
            self.collapse?.cancel()
            if self.expanded && self.style.presentation.islandPinned {
                self.changeAppearance { $0.presentation.islandPinned = false }
            } else {
                self.setExpanded(!self.expanded)
                if self.expanded && !self.targetFrame.contains(NSEvent.mouseLocation) { self.scheduleCollapse() }
            }
        }
        islandView.onPin = { [weak self] in
            self?.changeAppearance { $0.presentation.islandPinned.toggle() }
        }
        islandView.onLineCount = { [weak self] count in
            self?.changeAppearance { $0.presentation.islandAppearance.expandedLineCount = count }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        apply(style)
    }
    deinit {
        collapse?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(_ value: LyricsAppearance) {
        let wasPinned = style.presentation.islandPinned
        style = value.normalized()
        islandView.apply(style)
        if style.presentation.islandPinned { collapse?.cancel(); expanded = true }
        else if wasPinned { expanded = false }
        reposition()
    }
    private func changeAppearance(_ change: (inout LyricsAppearance) -> Void) {
        var updated = style
        change(&updated)
        if let onAppearanceChange { onAppearanceChange(updated) }
        else { apply(updated) }
    }
    private func scheduleCollapse() {
        guard !style.presentation.islandPinned else { return }
        let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
        collapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func reposition() {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        var geometry = IslandGeometry(screen: screen)
        geometry.topOffset = style.presentation.islandAppearance.topOffset
        islandView.geometry = geometry
        islandView.expanded = expanded
        resizeToFitContent()
    }
    private func resizeToFitContent() {
        let target = targetFrame
        if target != frame { setFrame(target, display: true) }
    }
    private var targetFrame: NSRect {
        let options = style.presentation.islandAppearance
        let width = islandView.geometry.frame(expanded: expanded, width: style.presentation.islandWidth,
            height: 1, compactWidth: options.compactWidth).width
        let height = islandView.preferredHeight(width: width, expanded: expanded)
        return islandView.geometry.frame(expanded: expanded, width: style.presentation.islandWidth,
            height: height, compactWidth: options.compactWidth, compactHeight: height)
    }
    func setExpanded(_ value: Bool, animated: Bool = true) {
        guard value || !style.presentation.islandPinned else { return }
        guard expanded != value else { return }
        expanded = value
        islandView.expanded = value
        let frame = targetFrame
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else { setFrame(frame, display: true) }
    }
}

final class IslandView: NSView {
    let controls = PlaybackControls(dark: true)
    let current = LyricsTextField("")
    let next = LyricsTextField("")
    let textViewport = LyricsTextViewport()
    let compact = NSButton()
    private let status = NSImageView()
    let expansion = NSButton()
    let pin = NSButton()
    let lineCount = NSSegmentedControl(labels: ["2 行", "5 行"], trackingMode: .selectOne, target: nil, action: nil)
    private let contextFields = (0..<4).map { _ in LyricsTextField("") }
    private(set) var visibleRows: [LyricsTextField] = []
    private(set) var currentRowIndex = 0
    private let track = NSTextField(labelWithString: "LyricGlass")
    private let settings = NSButton()
    private let railLine = NSView()
    private let progress = NSView()
    private let progressTrack = NSView()
    private var style = LyricsAppearance()
    private var tracking: NSTrackingArea?
    private var fraction: CGFloat = 0
    private var context: [String] = []
    private var contextIndex = 0
    private var focusCurrent = true
    var onPreferredHeightChange: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onExpand: (() -> Void)?
    var onPin: (() -> Void)?
    var onLineCount: ((Int) -> Void)?
    var onSettings: (() -> Void)?
    var geometry = IslandGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)) {
        didSet { updateCompactText(); focusCurrent = true; needsLayout = true }
    }
    var expanded = false {
        didSet {
            guard oldValue != expanded else { return }
            rebuildRows(); updateVisibility(); needsLayout = true
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1).cgColor
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        setAccessibilityElement(false)
        setAccessibilityLabel("LyricGlass 顶部歌词")
        for (button, symbol, title, action) in [
            (settings, "gearshape", "歌词设置", #selector(openSettings)),
            (expansion, "chevron.up", "收起为胶囊", #selector(toggleExpansion)),
            (pin, "pin", "锁定展开", #selector(togglePin))
        ] {
            button.isBordered = false; button.contentTintColor = .lightGray
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.target = self; button.action = action
            button.setAccessibilityLabel(title); button.toolTip = title
        }
        compact.isBordered = false; compact.contentTintColor = .white
        compact.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        compact.imagePosition = .imageLeading; compact.alignment = .left
        compact.cell?.lineBreakMode = .byTruncatingTail
        compact.target = self; compact.action = #selector(toggleExpansion)
        compact.setAccessibilityLabel("展开歌词")
        status.contentTintColor = .lightGray
        lineCount.controlSize = .small; lineCount.segmentStyle = .rounded
        lineCount.appearance = NSAppearance(named: .darkAqua)
        lineCount.target = self; lineCount.action = #selector(selectLineCount(_:))
        lineCount.setAccessibilityLabel("展开歌词行数")
        lineCount.toolTip = "选择展开后的两行或五行布局"
        track.font = .systemFont(ofSize: 11, weight: .medium); track.textColor = .lightGray
        track.lineBreakMode = .byTruncatingTail; track.maximumNumberOfLines = 1
        for label in [current, next] + contextFields { textViewport.textDocument.addSubview(label) }
        for view in [progressTrack, progress, railLine] { view.wantsLayer = true }
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progress.layer?.backgroundColor = NSColor(hex: "FFF2F6")!.withAlphaComponent(0.7).cgColor
        railLine.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        for view in [compact, status, track, textViewport, settings, expansion, pin, lineCount, controls, railLine, progressTrack, progress] { addSubview(view) }
        rebuildRows(); updateVisibility()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var primarySize: CGFloat { min(32, max(16, style.primarySize * 0.75)) }
    private var secondarySize: CGFloat { min(24, max(12, style.secondarySize * 0.75)) }
    private var gap: CGFloat { min(12, max(4, style.lineGap)) }
    private var fiveLine: Bool { style.presentation.islandAppearance.expandedLineCount == 5 }
    private func rowContents(expanded: Bool) -> [(text: String, distance: Int)] {
        if !expanded { return [] }
        if !fiveLine {
            var rows = [(current.stringValue, 0)]
            if style.presentation.showNextLine && !next.stringValue.isEmpty { rows.append((next.stringValue, 1)) }
            return rows
        }
        return context.enumerated().map { ($0.element, $0.offset - contextIndex) }
    }
    private func styledText(_ text: String, distance: Int, expanded: Bool) -> NSAttributedString {
        let active = distance == 0
        let far = abs(distance) > 1
        let size = active ? primarySize : (far ? max(12, secondarySize * 0.9) : secondarySize)
        let color = active ? NSColor(hex: "FFF2F6")! : NSColor.white.withAlphaComponent(far ? 0.35 : 0.65)
        return LyricsTypography.attributedText(text, style: style, size: size,
            bold: active && style.bold, color: color, alignment: fiveLine ? .left : .center)
    }
    private func rebuildRows() {
        let data = rowContents(expanded: expanded)
        for label in [current, next] + contextFields { label.isHidden = true }
        visibleRows = []
        var spare = 0
        for row in data {
            let label: LyricsTextField
            if row.distance == 0 { label = current; currentRowIndex = visibleRows.count }
            else if row.distance == 1 { label = next }
            else { label = contextFields[spare]; spare += 1 }
            let value = styledText(row.text, distance: row.distance, expanded: expanded)
            if !label.attributedStringValue.isEqual(to: value) { label.attributedStringValue = value }
            label.alignment = fiveLine ? .left : .center
            label.setAccessibilityLabel(row.distance == 0 ? "当前歌词" : (row.distance < 0 ? "之前的歌词" : "后续歌词"))
            label.isHidden = false
            visibleRows.append(label)
        }
        textViewport.textDocument.setAccessibilityChildren(visibleRows)
        textViewport.resetPosition(); focusCurrent = true
    }
    private func textWidth(_ width: CGFloat, expanded: Bool) -> CGFloat {
        max(1, width - (fiveLine && style.presentation.showControls ? 100 : 32))
    }
    func preferredHeight(width: CGFloat, expanded: Bool) -> CGFloat {
        if !expanded { return style.presentation.islandAppearance.compactHeight }
        let textWidth = textWidth(width, expanded: expanded)
        let heights: [CGFloat]
        if expanded == self.expanded {
            heights = visibleRows.map { $0.height(fittingWidth: textWidth) }
        } else {
            heights = rowContents(expanded: expanded).map { row in
                let field = LyricsTextField("")
                field.attributedStringValue = styledText(row.text, distance: row.distance, expanded: expanded)
                return field.height(fittingWidth: textWidth)
            }
        }
        let text = heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * gap
        let preferred = geometry.contentTopInset + 24 + 4 + text + 12
        let minimum: CGFloat = fiveLine && style.presentation.showControls ? geometry.contentTopInset + 128 : geometry.contentTopInset + 56
        return max(minimum, min(preferred, style.presentation.islandAppearance.expandedMaxHeight))
    }
    var expandedHeight: CGFloat {
        let width = geometry.frame(expanded: true, width: style.presentation.islandWidth, height: 1,
            compactWidth: style.presentation.islandAppearance.compactWidth).width
        return preferredHeight(width: width, expanded: true)
    }
    func apply(_ value: LyricsAppearance) {
        style = value.normalized()
        updateCompactText()
        rebuildRows(); updateVisibility(); needsLayout = true
    }
    func show(current text: String, next upcoming: String, title: String, artist: String,
              playing: Bool, canControl: Bool, position: Double, duration: Double, error: String,
              context suppliedContext: [String] = [], currentIndex: Int = 0) {
        let lines = suppliedContext.isEmpty ? [text, upcoming].filter { !$0.isEmpty } : Array(suppliedContext.prefix(5))
        let index = min(max(0, currentIndex), max(0, lines.count - 1))
        let changed = current.stringValue != text || next.stringValue != upcoming || context != lines || contextIndex != index
        if changed {
            current.stringValue = text; next.stringValue = upcoming
            context = lines; contextIndex = index
            rebuildRows()
        }
        let metadata = error.isEmpty ? [title, artist].filter { !$0.isEmpty }.joined(separator: " · ") : error
        if track.stringValue != metadata { track.stringValue = metadata }
        track.toolTip = metadata
        updateCompactText()
        compact.toolTip = [title, text, error].filter { !$0.isEmpty }.joined(separator: "\n")
        status.image = NSImage(systemSymbolName: playing ? "waveform" : "pause.fill", accessibilityDescription: playing ? "播放中" : "已暂停")
        controls.update(playing: playing, enabled: canControl)
        fraction = duration > 0 && position.isFinite ? CGFloat(min(1, max(0, position / duration))) : 0
        if changed { onPreferredHeightChange?() }
        needsLayout = true
    }
    private func updateCompactText() {
        let text = geometry.hasNotch ? "" : "  " + current.stringValue
        let size = min(12, max(10, style.presentation.islandAppearance.compactHeight - 6))
        let value = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white])
        if !compact.attributedTitle.isEqual(to: value) { compact.attributedTitle = value }
        compact.setAccessibilityValue(current.stringValue)
    }
    private func updateVisibility() {
        compact.isHidden = expanded; status.isHidden = expanded
        for view in [track, textViewport, settings, expansion, pin, lineCount, progressTrack, progress] { view.isHidden = !expanded }
        controls.isHidden = !expanded || !style.presentation.showControls
        controls.orientation = fiveLine ? .vertical : .horizontal
        railLine.isHidden = !expanded || !fiveLine || !style.presentation.showControls
        lineCount.selectedSegment = fiveLine ? 1 : 0
        let title = style.presentation.islandPinned ? "解除展开锁定" : "锁定展开"
        pin.image = NSImage(systemSymbolName: style.presentation.islandPinned ? "pin.fill" : "pin", accessibilityDescription: title)
        pin.contentTintColor = style.presentation.islandPinned ? NSColor(hex: "FFF2F6") : .lightGray
        pin.setAccessibilityLabel(title); pin.toolTip = title
    }
    override func layout() {
        super.layout()
        guard bounds.width > 100, bounds.height > 0 else { return }
        layer?.cornerRadius = style.presentation.islandAppearance.shape.radius(height: bounds.height, expanded: expanded)
        if !expanded {
            compact.frame = NSRect(x: 10, y: 2, width: max(0, bounds.width - 44), height: max(0, bounds.height - 4))
            let size = min(14, bounds.height - 6)
            status.frame = NSRect(x: bounds.width - 28, y: (bounds.height - size) / 2, width: size, height: size)
            return
        }
        let top = bounds.height - geometry.contentTopInset
        let textWidth = textWidth(bounds.width, expanded: expanded)
        settings.frame = NSRect(x: bounds.width - 42, y: top - 23, width: 24, height: 24)
        expansion.frame = NSRect(x: bounds.width - 70, y: top - 23, width: 24, height: 24)
        pin.frame = NSRect(x: bounds.width - 98, y: top - 23, width: 24, height: 24)
        lineCount.frame = NSRect(x: bounds.width - 182, y: top - 21, width: 78, height: 20)
        let toolbarWidth: CGFloat = !fiveLine && style.presentation.showControls ? 118 : 0
        track.frame = NSRect(x: 16, y: top - 18, width: max(1, bounds.width - 204 - toolbarWidth), height: 16)
        if fiveLine && style.presentation.showControls {
            railLine.frame = NSRect(x: bounds.width - 65, y: 12, width: 1, height: max(0, top - 12))
            let available = max(0, top - 28 - 12)
            controls.frame = NSRect(x: bounds.width - 45, y: 12 + max(0, (available - 96) / 2), width: 28, height: min(96, available))
        } else {
            controls.frame = NSRect(x: bounds.width - 302, y: top - 23, width: 112, height: 24)
        }
        let widthChanged = textViewport.frame.width != textWidth
        textViewport.frame = NSRect(x: 16, y: 12, width: textWidth, height: max(0, top - 28 - 12))
        let heights = visibleRows.map { $0.height(fittingWidth: textWidth) }
        let total = heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * gap
        textViewport.fitDocument(height: total)
        var y = textViewport.textDocument.bounds.height
        for (label, height) in zip(visibleRows, heights) {
            y -= height
            label.frame = NSRect(x: 0, y: y, width: textWidth, height: height)
            y -= gap
        }
        if (focusCurrent || widthChanged), !current.isHidden {
            let maxY = max(0, textViewport.textDocument.bounds.height - textViewport.contentSize.height)
            let y = min(maxY, max(0, current.frame.maxY - textViewport.contentSize.height))
            textViewport.contentView.scroll(to: NSPoint(x: 0, y: y))
            textViewport.reflectScrolledClipView(textViewport.contentView)
            focusCurrent = false
        }
        progressTrack.frame = NSRect(x: 16, y: 3, width: max(0, bounds.width - 32), height: 1.5)
        progress.frame = NSRect(x: 16, y: 3, width: max(0, bounds.width - 32) * fraction, height: 1.5)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { if !expanded { onExpand?() } }
    @objc private func toggleExpansion() { onExpand?() }
    @objc private func togglePin() { onPin?() }
    @objc private func selectLineCount(_ sender: NSSegmentedControl) { onLineCount?(sender.selectedSegment == 1 ? 5 : 2) }
    @objc private func openSettings() { onSettings?() }
}
