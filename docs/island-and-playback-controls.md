# 顶部灵动岛、播放控制与歌词布局

本机功能版本 v0.6.2，基于已发布的 v0.5.2。现有中英文独立字体、歌词来源与缓存、雨滴设置保留。默认同时显示桌面歌词与顶部灵动岛。

## 使用

- 设置 → 外观 → 显示方式：同时显示、仅桌面、仅灵动岛
- 灵动岛固定在主屏顶部中心，悬停或点击展开，离开后延迟 0.35 秒收起；「保持展开」可固定展开状态
- 展开后显示歌名、歌手、当前句、下一句、进度，以及上一首/播放暂停/下一首。设置按钮打开完整设置
- 桌面歌词悬停时在外侧显示播放工具条，不占常驻歌词高度；设置 → 播放与歌词 → 播放控制提供常驻按钮
- 两句歌词间距 0–64pt、桌面歌词宽度 480–1400pt；顶部收起宽度 180–1000pt、高度 18–64pt，展开宽度 320–1000pt、最大高度 160–720pt，可隐藏下一句或播放按钮
- 顶部窗口支持胶囊、圆角长方形、长方形，可调整距屏幕顶部 0–80pt，收起默认 420×24pt；有刘海时保留镜头所需安全区域
- 字体、显示方式和尺寸自动保存，主题预设保留显示方式、窗口宽度与可见内容选项；升级从旧设置迁移时保留原有字体、颜色和雨滴偏好
- 鼠标穿透与置顶设置控制桌面歌词；灵动岛保持可操作。菜单栏可统一隐藏/显示，重新打开 app 会恢复主屏位置

## 播放器控制

读取两个播放器的随应用发布的 scripting dictionary，使用原生 Apple Events。Spotify 的事件类为 `spfy`，Apple Music 为 `hook`；三种命令 ID 为 `Prev`、`PlPs`、`Next`。命令只在用户点击时发送，目标是点击当时界面正在跟随的播放器。

播放器未运行或未连接曲目时按钮禁用。请求处理中禁用重复点击；发生拒绝或超时时显示错误，不自动重试或转发给另一个播放器。成功后重新采样，不假造播放状态。观察逻辑仍只读取，不主动改变播放。示例歌词按钮操作仅作用于本地演示。

命令词典的本机核对路径：Spotify.app/Contents/Resources/Spotify.sdef、Music.app/Contents/Resources/Music.sdef。

## 屏幕处理

使用公开的 [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)、[auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc) 和右侧对应区域计算刘海宽度；展开文字放在摄像头遮挡区域以下。窗口使用公开的 [statusBar 层级](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/statusbar)。展开保持上边缘和水平中心不变，尺寸受屏幕范围约束；切换屏幕配置后重新定位。系统「减少动态效果」开启时跳过展开动画。

## 验证

`scripts/check.sh` 覆盖原有歌词、缓存、播放器识别与新命令的目标隔离、词典事件类、未运行、拒绝、超时不重试。`scripts/check-appearance.sh` 使用独立临时偏好域，覆盖设置到实际视图的间距与宽度、单句高度、双窗口按钮回调、固定展开/收起、旧设置和跨进程恢复，以及带刘海、负坐标、小屏幕的布局模拟。

Intel 包含在 Universal 构建中；模拟刘海布局不能替代所有机型实测。实际桌面检查结果记录于本轮验证报告。
