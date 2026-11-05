import AppKit
import QuartzCore

struct IslandGeometry {
    var screenFrame: NSRect
    var topInset: CGFloat
    var notchWidth: CGFloat
    var notchCenterX: CGFloat
    var topOffset: CGFloat = 0

    init(screenFrame: NSRect, topInset: CGFloat = 0, notchWidth: CGFloat = 0, notchCenterX: CGFloat? = nil) {
        self.screenFrame = screenFrame; self.topInset = topInset; self.notchWidth = notchWidth
        self.notchCenterX = notchCenterX ?? screenFrame.midX
    }
    init(screen: NSScreen) {
        screenFrame = screen.frame
        topInset = screen.safeAreaInsets.top
        notchCenterX = screen.frame.midX
        if topInset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
            notchCenterX = (left.maxX + right.minX) / 2
        } else { notchWidth = 0 }
    }
    var hasNotch: Bool { topInset > topOffset }
    var notchFrame: NSRect {
        NSRect(x: notchCenterX - notchWidth / 2, y: screenFrame.maxY - topInset, width: notchWidth, height: topInset)
    }
    /// Keep lyrics on the left and reserve a separate play/pause wing on the right.
    func compactContentBounds(windowFrame: NSRect, lyricWidth: CGFloat = 160) -> NSRect {
        let safeRight = hasNotch ? min(windowFrame.width - 44, notchFrame.minX - windowFrame.minX) : windowFrame.width - 44
        return NSRect(x: 12, y: 0, width: max(0, min(lyricWidth, safeRight - 24)), height: windowFrame.height)
    }
    func compactControlBounds(windowFrame: NSRect) -> NSRect {
        let x = max(0, windowFrame.width - 44)
        return NSRect(x: x, y: 0, width: max(0, windowFrame.width - x), height: windowFrame.height)
    }
    var contentTopInset: CGFloat { hasNotch ? topInset - topOffset + 8 : 8 }
    func frame(expanded: Bool, width: CGFloat, height: CGFloat, compactWidth: CGFloat = 420, compactHeight: CGFloat = 24) -> NSRect {
        let actualHeight = min(expanded ? height : max(compactHeight, hasNotch ? topInset - topOffset : 0), max(1, screenFrame.height - topOffset - 12))
        let y = screenFrame.maxY - topOffset - actualHeight
        if hasNotch {
            let maximum = max(1, screenFrame.width - 24)
            let compactSpan = min(max(compactWidth, notchWidth + 168), maximum)
            // Keep every allowed capsule width inside the widest centered reading card.
            let readingWidth = min(1000, maximum)
            let readingLeft = min(screenFrame.maxX - 12 - readingWidth, max(screenFrame.minX + 12, notchCenterX - readingWidth / 2))
            let compactLeft = min(readingLeft + readingWidth - compactSpan, max(readingLeft, notchFrame.maxX + 44 - compactSpan))
            let compactRight = compactLeft + compactSpan
            if !expanded { return NSRect(x: compactLeft, y: y, width: compactSpan, height: actualHeight) }
            let minimumWidth = 2 * max(notchCenterX - compactLeft, compactRight - notchCenterX)
            let actualWidth = min(max(width, minimumWidth), max(1, screenFrame.width - 24))
            // Grow equally around the camera, including every point of the compact bar.
            let x = min(screenFrame.maxX - 12 - actualWidth, max(screenFrame.minX + 12, notchCenterX - actualWidth / 2))
            return NSRect(x: x, y: y, width: actualWidth, height: actualHeight)
        }
        let actualWidth = min(expanded ? max(width, compactWidth) : compactWidth, max(1, screenFrame.width - 24))
        return NSRect(x: screenFrame.midX - actualWidth / 2, y: y, width: actualWidth, height: actualHeight)
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
        didSet { islandView.controls.onAction = onPlaybackAction; islandView.onPlaybackAction = onPlaybackAction }
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
        hasShadow = expanded || !islandView.geometry.hasNotch
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
        hasShadow = expanded || !islandView.geometry.hasNotch
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
    let compact = MarqueeLyricsButton()
    let compactPlayPause = NSButton()
    let expansion = NSButton()
    let pin = NSButton()
    let lineCount = NSSegmentedControl(labels: ["2 行", "5 行"], trackingMode: .selectOne, target: nil, action: nil)
    private let contextFields = (0..<4).map { _ in LyricsTextField("") }
    private(set) var visibleRows: [LyricsTextField] = []
    private(set) var currentRowIndex = 0
    private let track = NSTextField(labelWithString: "LyricGlass")
    private let settings = NSButton()
    private let progress = NSView()
    private let progressTrack = NSView()
    private var style = LyricsAppearance()
    private var tracking: NSTrackingArea?
    private var trackedRect: NSRect?
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
    var onPlaybackAction: ((SettingsAction) -> Void)?
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
        compact.contentTintColor = .white
        compact.target = self; compact.action = #selector(toggleExpansion)
        compact.setAccessibilityLabel("展开歌词")
        compactPlayPause.isBordered = false; compactPlayPause.contentTintColor = .white
        compactPlayPause.target = self; compactPlayPause.action = #selector(togglePlayback)
        compactPlayPause.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放")
        compactPlayPause.setAccessibilityLabel("播放"); compactPlayPause.toolTip = "播放"
        lineCount.controlSize = .small; lineCount.segmentStyle = .rounded
        lineCount.appearance = NSAppearance(named: .darkAqua)
        lineCount.target = self; lineCount.action = #selector(selectLineCount(_:))
        lineCount.setAccessibilityLabel("展开歌词行数")
        lineCount.toolTip = "选择展开后的两行或五行布局"
        track.font = .systemFont(ofSize: 11, weight: .medium); track.textColor = .lightGray
        track.lineBreakMode = .byTruncatingTail; track.maximumNumberOfLines = 1; track.alignment = .center
        for label in [current, next] + contextFields { textViewport.textDocument.addSubview(label) }
        for view in [progressTrack, progress] { view.wantsLayer = true }
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progress.layer?.backgroundColor = NSColor(hex: "FFF2F6")!.withAlphaComponent(0.7).cgColor
        for view in [compact, compactPlayPause, track, textViewport, settings, expansion, pin, lineCount, controls, progressTrack, progress] { addSubview(view) }
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
        max(1, min(fiveLine ? 520 : 560, width - 48))
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
        let preferred = geometry.contentTopInset + 26 + text + 50
        let minimum: CGFloat = geometry.contentTopInset + 90
        return max(minimum, min(preferred, style.presentation.islandAppearance.expandedMaxHeight))
    }
    var expandedHeight: CGFloat {
        let width = geometry.frame(expanded: true, width: style.presentation.islandWidth, height: 1, compactWidth: style.presentation.islandAppearance.compactWidth).width
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
        let actionTitle = playing ? "暂停" : "播放"
        if compactPlayPause.toolTip != actionTitle {
            compactPlayPause.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: actionTitle)
            compactPlayPause.setAccessibilityLabel(actionTitle); compactPlayPause.toolTip = actionTitle
        }
        compactPlayPause.isEnabled = canControl
        controls.update(playing: playing, enabled: canControl)
        fraction = duration > 0 && position.isFinite ? CGFloat(min(1, max(0, position / duration))) : 0
        if changed { onPreferredHeightChange?() }
        needsLayout = true
    }
    private func updateCompactText() {
        let text = current.stringValue
        let size = min(12, max(10, style.presentation.islandAppearance.compactHeight - 6))
        let value = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white])
        if !compact.attributedTitle.isEqual(to: value) { compact.attributedTitle = value }
        compact.setAccessibilityValue(current.stringValue)
    }
    private func updateVisibility() {
        compact.isHidden = expanded; compactPlayPause.isHidden = expanded
        compact.animationEnabled = !expanded
        for view in [track, textViewport, settings, expansion, pin, lineCount] { view.isHidden = !expanded }
        progressTrack.alphaValue = 1
        progress.alphaValue = 1
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(expanded ? 0.12 : 0.10).cgColor
        progress.layer?.backgroundColor = expanded ? NSColor(hex: "FFF2F6")!.withAlphaComponent(0.7).cgColor : NSColor.white.cgColor
        controls.isHidden = !expanded || !style.presentation.showControls
        controls.orientation = .horizontal
        lineCount.selectedSegment = fiveLine ? 1 : 0
        let title = style.presentation.islandPinned ? "解除展开锁定" : "锁定展开"
        pin.image = NSImage(systemSymbolName: style.presentation.islandPinned ? "pin.fill" : "pin", accessibilityDescription: title)
        pin.contentTintColor = style.presentation.islandPinned ? NSColor(hex: "FFF2F6") : .lightGray
        pin.setAccessibilityLabel(title); pin.toolTip = title
    }
    override func layout() {
        super.layout()
        guard bounds.width > 100, bounds.height > 0 else { return }
        let wrapsNotch = !expanded && geometry.hasNotch
        layer?.backgroundColor = wrapsNotch ? NSColor.black.cgColor : NSColor(calibratedWhite: 0.025, alpha: 1).cgColor
        layer?.borderWidth = wrapsNotch ? 0 : 0.5
        layer?.maskedCorners = wrapsNotch ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.cornerRadius = style.presentation.islandAppearance.shape.radius(height: bounds.height, expanded: expanded)
        let windowFrame = window?.frame ?? geometry.frame(expanded: false, width: style.presentation.islandWidth, height: bounds.height,
            compactWidth: style.presentation.islandAppearance.compactWidth, compactHeight: style.presentation.islandAppearance.compactHeight)
        let compactBounds = geometry.compactContentBounds(windowFrame: windowFrame, lyricWidth: style.presentation.islandAppearance.compactLyricWidth)
        let barHeight: CGFloat = expanded ? 1.5 : 1
        let barY: CGFloat = expanded ? 3 : (bounds.height < 22 ? 1 : 2)
        let barWidth = max(0, bounds.width - 32)
        progressTrack.frame = NSRect(x: 16, y: barY, width: barWidth, height: barHeight)
        progress.frame = NSRect(x: 16, y: barY, width: barWidth * fraction, height: barHeight)
        let cutout = geometry.notchFrame.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
        for view in [progressTrack, progress] {
            view.layer?.cornerRadius = barHeight / 2
            let overlap = view.frame.intersection(cutout)
            if !expanded && geometry.hasNotch && !overlap.isEmpty {
                let path = CGMutablePath(); path.addRect(view.bounds)
                path.addRect(overlap.offsetBy(dx: -view.frame.minX, dy: -view.frame.minY))
                let mask = CAShapeLayer(); mask.path = path; mask.fillRule = .evenOdd
                view.layer?.mask = mask
            } else { view.layer?.mask = nil }
        }
        if !expanded {
            compact.frame = NSRect(x: compactBounds.minX, y: 3, width: compactBounds.width, height: max(0, bounds.height - 6))
            let control = geometry.compactControlBounds(windowFrame: windowFrame)
            let size = min(32, bounds.height - 4)
            compactPlayPause.frame = NSRect(x: control.midX - size / 2, y: (bounds.height - size) / 2, width: size, height: size)
            updateTrackingAreas()
            return
        }
        let top = bounds.height - geometry.contentTopInset
        let textWidth = textWidth(bounds.width, expanded: expanded)
        settings.frame = NSRect(x: bounds.width - 42, y: 13, width: 24, height: 24)
        expansion.frame = NSRect(x: bounds.width - 70, y: 13, width: 24, height: 24)
        pin.frame = NSRect(x: bounds.width - 98, y: 13, width: 24, height: 24)
        lineCount.frame = NSRect(x: 16, y: 15, width: 78, height: 20)
        track.frame = NSRect(x: 24, y: top - 18, width: max(1, bounds.width - 48), height: 16)
        controls.frame = NSRect(x: (bounds.width - 112) / 2, y: 12, width: 112, height: 26)
        let widthChanged = textViewport.frame.width != textWidth
        textViewport.frame = NSRect(x: (bounds.width - textWidth) / 2, y: 50, width: textWidth, height: max(0, top - 26 - 50))
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
        updateTrackingAreas()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        let rect = expanded ? bounds : compact.frame
        guard trackedRect != rect else { return }
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); tracking = area; trackedRect = rect
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { if !expanded { onExpand?() } }
    @objc private func toggleExpansion() { onExpand?() }
    @objc private func togglePlayback() { onPlaybackAction?(.togglePlayback) }
    @objc private func togglePin() { onPin?() }
    @objc private func selectLineCount(_ sender: NSSegmentedControl) { onLineCount?(sender.selectedSegment == 1 ? 5 : 2) }
    @objc private func openSettings() { onSettings?() }
}
