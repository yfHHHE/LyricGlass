import AppKit

enum QuickMenuAction: Int { case toggleVisible, toggleLock, settings, quit }

final class QuickMenu: NSObject {
    let menu = NSMenu()
    private let onAction: (QuickMenuAction) -> Void
    init(onAction: @escaping (QuickMenuAction) -> Void) { self.onAction = onAction; super.init() }
    func update(visible: Bool, locked: Bool) {
        menu.removeAllItems()
        add(visible ? "隐藏歌词" : "显示歌词", .toggleVisible)
        add("锁定位置", .toggleLock, checked: locked)
        menu.addItem(.separator())
        add("设置…", .settings, key: ",")
        menu.addItem(.separator())
        add("退出 LyricGlass", .quit, key: "q")
    }
    private func add(_ title: String, _ action: QuickMenuAction, checked: Bool = false, key: String = "") {
        let item = NSMenuItem(title: title, action: #selector(chooseItem(_:)), keyEquivalent: key)
        item.target = self; item.tag = action.rawValue; item.state = checked ? .on : .off
        menu.addItem(item)
    }
    @objc private func chooseItem(_ sender: NSMenuItem) {
        if let action = QuickMenuAction(rawValue: sender.tag) { onAction(action) }
    }
}
