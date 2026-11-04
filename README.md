# LyricGlass

<img src="Resources/AppIcon.png" width="96" alt="LyricGlass 图标">

Spotify 和 Apple Music 的 macOS 桌面歌词与顶部胶囊。自动跟随播放，顶部展开可选两行或五行，支持独立锁定展开。

**[下载最新测试版](https://github.com/yfHHHE/LyricGlass/releases)** · [首次运行说明](docs/首次运行.txt)

## 安装

要求 **macOS 13+，使用 Spotify 或系统“音乐”桌面客户端**。安装包为 Universal，包含 Apple Silicon（arm64）和 Intel（x86_64）。当前界面为中文。

1. 在 [Releases](https://github.com/yfHHHE/LyricGlass/releases) 下载 `.dmg`，打开后把 `LyricGlass.app` 拖入 Applications；也可下载 ZIP 并解压
2. 打开 LyricGlass，首次启动默认“自动识别”；允许读取正在运行的 Spotify / 音乐的“自动化”权限
3. 在 Spotify 或 Apple Music 桌面端播放歌曲，app 会自动跟随；在“设置 → 播放与歌词”中也可固定使用某一个播放器

**当前版本未使用 Apple Developer ID 签名，也未公证。** macOS 可能阻止首次打开。确认文件来自本项目 Release 后，先尝试打开一次，再到“系统设置 → 隐私与安全性”找到 LyricGlass，选择“仍要打开”。详见 [Apple 官方说明](https://support.apple.com/102445)。受组织管理的 Mac 可能不允许此操作。

下载使用不需要 Xcode、命令行工具、Spotify / Apple 开发者账号或 API key。

## 功能与操作

- 长歌词默认自动换行，保留字号；桌面与展开的灵动岛随内容调整高度，超过屏幕高度时可滚动查看完整内容
- 顶部收起时保持原来的单行小胶囊；悬停或点击展开，展开可选居中两行（A）或靠左五行（D），默认两行
- 展开行数和锁定独立控制：点图钉锁定后保持展开，解锁后回到胶囊；未锁定时移开鼠标自动收起，点击展开不会隐式锁定；行数与锁定状态自动保存
- 五行从同一播放时间轴读取上下文，当前句高亮；前奏、间奏与歌曲首尾自动调整，拖动播放进度和歌词时间偏移同时生效
- 「外观 → 显示方式」可选桌面歌词与灵动岛、仅桌面歌词、仅灵动岛
- 上一首、播放/暂停、下一首：位于顶部双行标题栏、展开后的右侧、鼠标悬停的桌面歌词和「播放与歌词」设置页，只控制当前跟随的播放器
- 顶部胶囊宽度 180–1000pt、高度 18–64pt，展开宽度 320–1000pt、最大高度 160–720pt；展开后随内容换行调整高度，支持顶部偏移及三种展开形状，收起时始终为胶囊，刘海屏自动避开摄像头
- 两句歌词间距 0–64pt，按实际字形去掉多余字体留白；桌面窗口不再为播放按钮预留常驻高度，悬停时在外侧显示工具条
- 桌面宽度 480–1400pt；可隐藏下一句和播放按钮，外观自动保存
- 跟随所选 Spotify / Apple Music 的歌曲、暂停、继续、切歌与进度跳转
- 默认自动识别正在播放的 Spotify / Apple Music；另一方新开始播放时自动切换，双方暂停时保留当前歌词
- 设置可选择“自动识别 / Spotify / Apple Music”并记住模式，显示实际跟随的播放器
- 原生分类设置：实时预览、中英文字体独立选择、独立字号与颜色、透明/纯色/毛玻璃背景；外观自动保存
- 23 个字体选项，内置 OpenDyslexic、Inter、思源/Noto、霞鹜文楷等 11 个家族；Apple 与商业字体使用系统或本机授权版本
- 可开关的雨滴动画：静止、播放时摇摆；实验性音频律动根据当前播放器的音频强弱运动，需 macOS 14.2+ 及主动授权
- 透明双行歌词，支持拖动、置顶、鼠标穿透；设置详情见 [原生设置](docs/appearance-settings.md)
- 鼠标悬停显示播放工具条，提示可查看歌曲、进度与同步状态
- 右键歌词或点击菜单栏气泡，只保留显示/隐藏、锁定位置、设置、退出四项；播放器、歌词同步和缓存操作集中在设置页
- 歌词每次可提前/延后 0.5 秒，范围 ±15 秒，切歌归零
- 无匹配歌词时，支持为当前歌曲导入 UTF-8 `.lrc`
- 每首最多并行查询两个来源：优先 LRCLIB 和 QQ Music，再尝试 lrcmux、酷狗、网易；合格的同步歌词先返回并取消剩余请求
- 每个来源包含搜索、下载和重试的总预算为 4 秒；来源故障短暂退避，普通歌词不会挡住后续同步歌词
- 支持繁简、部分常见中英文艺名、来源提供的歌手别名和合作歌手匹配，保留版本与曲长校验
- 同一录音的缓存可跨播放器复用，容许曲长元数据的小幅精度差；兼容旧版缓存，重启后可离线读取

![双行歌词与雨滴摇摆预览](docs/images/lyrics-pet-demo.gif)

图示为循环摇摆演示，不是音频节拍检测。雨滴开关和动作在「设置 → 雨滴」中调整，详见 [雨滴设置](docs/raindrop-companion.md)。真实播放器音频采集尚待用户主动授权后验证，不保证精确 BPM 跟拍。

## 常见问题

**打开后找不到窗口？**

LyricGlass 是菜单栏 app，不显示常驻 Dock 图标。启动时歌词出现在主屏底部；再次打开 app 会把歌词显示并移回主屏底部。也可打开“设置 → 外观 → 恢复主屏位置”。把 app 放在“应用程序”后，可从 Finder 或 Spotlight 打开；系统目录不可写时也可放入自己的 `~/Applications/`。

**没有读取到播放器？**

确认“设置 → 播放与歌词”使用“自动识别”或固定了实际使用的播放器，并播放一首歌。自动模式会分别读取两个已运行的客户端，因此两者都运行时可能分别需要授权。若权限曾被拒绝，到“系统设置 → 隐私与安全性 → 自动化 → LyricGlass”允许对应的 Spotify / 音乐，再点“播放与歌词”中的“重试连接”。拒绝一方的权限不会阻止另一方正常播放时显示歌词。

**两个播放器都在播放时跟随谁？**

自动模式跟随最近检测到由暂停或停止变为播放的一方；如果同一轮采样发现双方都在播放，就保持当前来源。刚启动时无法知道谁先播放，优先上次跟随的一方，没有记录时优先 Spotify。双方都暂停时保留当前来源和暂停位置。自动识别不会更改播放，也不会启动未运行的客户端；需要固定来源时，从“设置 → 播放与歌词”选择 Spotify 或 Apple Music。

**Apple Music 流媒体歌曲没有曲目信息？**

部分新版 macOS 对未加入资料库的流媒体歌曲无法读取 `current track`，见 [Apple 开发者论坛](https://developer.apple.com/forums/thread/798267)。LyricGlass 会用 Music 的本机播放通知补充曲名、歌手、专辑和曲长，继续从播放器读取实际进度。如果先播放歌曲、后启动 LyricGlass，且尚未收到通知，请在 Music 暂停后继续一次或切歌。曲目信息不足时会提示，不把上一首歌词套到新歌。

**找不到歌词或显示服务繁忙？**

歌词来自 [LRCLIB](https://lrclib.net/docs)、网易、QQ Music、酷狗和 [lrcmux](https://lrcmux.dev/)，并非直接获取 Spotify 或 Apple Music 内置的歌词。应用每首最多同时查询两个来源，保留歌手、版本和曲长校验，拿到合格的同步歌词后取消剩余请求。服务繁忙时遵守 `Retry-After`，来源每轮最多等待 4 秒；来源业务错误或网络故障暂时退避 20 秒，“播放与歌词”中的“重新匹配”可主动重试，但不会跳过服务端限流。

网易、QQ、酷狗使用的是社区采用的直接端点，可能因地区、服务调整或访问限制不可用。程序不会使用你的登录 Cookie 或账号，也不会绕过服务的验证码或登录要求。仍无结果时可导入本地 LRC。新增来源的调研及固定样本验证见 [歌词来源与覆盖](docs/lyrics-sources.md)。

lrcmux 是聚合服务，可能与直接来源使用相同的上游，来源数量不等于独立歌词数量。应用保留其实际返回的曲目信息和上游名称，例如 `lrcmux · KuGou`，再用同样的录音规则校验；不使用请求参数伪造匹配信息。

Spotify 和歌词库可能采用不同艺名，例如 Amazing Show / 美秀集团。v0.2.1 已补上这组对应；此前《愛情的大壞蛋》在 QQ 有同步歌词，但被歌手身份校验误排除了。

**全屏或其他设备播放能用吗？**

支持本机 Spotify 和系统“音乐”桌面端；网页版、其他 Spotify Connect / AirPlay 设备的远程播放、独占全屏窗口尚未验证。

**退出后为什么设置恢复默认？**

自动匹配成功的同步歌词和播放器模式会保存在本机。v0.4.0 升级后首次默认自动识别；之后明确固定某个播放器的选择会保存。字体、颜色、字号、背景、置顶和鼠标穿透会自动保存。手工 LRC 的歌曲关联、窗口位置和偏移仍只保留在本次运行中。

**歌词缓存在哪里，如何清理？**

缓存位于 `~/Library/Application Support/LyricGlass/Lyrics/`，包含歌曲元数据、歌词正文、时间轴和来源。有效期 30 天，最多保存 200 首。点击“设置 → 播放与歌词 → 清空歌词缓存”可删除自动缓存并重新匹配当前歌曲；“重新匹配”会优先重新请求网络，网络全部不可用时保留已验证的缓存作为兜底。

缓存按归一化歌名、歌手、专辑和曲长分桶，不依赖播放器 ID。同一录音的曲长变化不超过 2 秒时会重新校验并尝试复用，live/remix、其他歌手、其他专辑及明显不同曲长不会共用。旧版缓存继续按原有到期时间读取，不会因升级自动清空或续期；手动重新匹配优先尝试上次验证成功的来源。

## 隐私与第三方服务

- 自动模式通过 Apple events 探测两个已运行播放器的播放状态，再读取当前选中方的曲目与进度；手动模式仅轮询指定一方
- 监听 Music 的本机播放通知，以补充流媒体曲目信息；不读取账号凭据
- 向 `lrclib.net`、`music.163.com`、`c.y.qq.com`、`lyrics.kugou.com` 和 `api.lrcmux.dev` 发送匹配所需的歌曲元数据或歌词来源 ID
- 网易可能建立仅属于本 app 的匿名内存会话，不读取浏览器或 Spotify 的登录 Cookie
- 不上传音频、Spotify / Apple Music token、账号信息或导入的本地 LRC
- 实验性音频律动只在主动点击「连接音乐音频」后读取所选播放器的输出，在本机分析强弱，不使用麦克风、不保存音频；重启后需重新连接
- 没有项目自行添加的遥测或分析服务；自动匹配成功的同步歌词按上述规则保存在本机，不上传到项目仓库
- 安装包不内置完整歌词库，预览使用示例歌词片段；第三方服务内容及权利归各自权利人

本项目独立于 Spotify 和 Apple，与其无隶属关系。源码公开供查看，尚未指定开源许可证。

## 从源码构建

需要 macOS 和 Apple Command Line Tools / Swift 5.9+，没有外部 Swift 包依赖。

```sh
./run.command                  # 构建并打开本机构架版本
./run.command --demo           # 使用示例歌词，不读取播放器、不请求网络
./scripts/check.sh             # 核心及多源回退回归，不访问网络
./scripts/check-pet-audio.sh    # 合成音频强弱测试，不启动录制
./scripts/check-appearance.sh   # 原生设置与歌词显示检查，需要桌面会话
./scripts/build-app.sh --universal
./scripts/package-release.sh   # 生成 Universal DMG、ZIP 和 SHA256SUMS.txt
```

app 输出在 `dist/LyricGlass.app`。Release 包仅为本地 ad-hoc 签名，打包脚本不会自动申请证书或公证。

可选诊断：

```sh
dist/LyricGlass.app/Contents/MacOS/LyricGlass --check-lyrics
dist/LyricGlass.app/Contents/MacOS/LyricGlass --check-lyrics --title Galaxies --artist 'Laura Veirs' --album 'Year of Meteors' --duration 216 --fresh
dist/LyricGlass.app/Contents/MacOS/LyricGlass --diagnose-spotify
dist/LyricGlass.app/Contents/MacOS/LyricGlass --diagnose-player --player apple-music --watch 20
dist/LyricGlass.app/Contents/MacOS/LyricGlass --diagnose-player --player auto --watch 20
```

`--check-lyrics` 默认测试固定公开曲目，也可指定歌曲；仅输出匹配元数据、来源及上游、缓存命中、耗时和时间戳行数，不打印歌词正文。可用 `--source lrclib|netease|qq|kugou|lrcmux` 单独检查来源，用 `--cache-dir <目录>` 指定诊断缓存位置。`--diagnose-player --player auto|spotify|apple-music` 在本地输出模式、实际来源和当前播放状态，默认自动识别；`--watch 20` 连续监听 20 秒，最多 120 秒。保留 `--diagnose-spotify` 兼容旧命令。诊断权限可能记在宿主终端名下，以 app 实际运行的授权为准。

## 同步方式与验证范围

每 0.5 秒探测播放器并读取当前来源，在两次采样间用 monotonic clock 推进；读数超过 2 秒未刷新则冻结。自动模式不会把来源超时后恢复视作新开始播放；超时来源稍后重试，被拒绝的权限等待用户从设置中重试。Apple Music 曲长使用秒，Spotify 返回的毫秒单独换算。按歌名、歌手和时长匹配歌词，容许时长差 ±2 秒，保留 live/remix 等版本名，并做繁简归一。合作歌手按名字集合匹配，来源只列主唱时还必须匹配专辑。艺名支持少量明确的对照及来源返回的别名，未收录的别名仍可能漏匹配。切歌或切换播放器时取消旧请求并校验歌曲身份，避免旧请求覆盖新歌。

回归覆盖时间戳、双播放器的单位与录音身份、暂停与跳转、Music 流媒体通知、权限拒绝、艺名及合作歌手、多源回退、服务重试与长时间限流、请求取消、离线重启及缓存。Spotify 播放读取和 Apple Music 实播元数据、暂停及歌词匹配已在 Apple Silicon 上验证；Intel 构建和其他 macOS 版本尚未完成硬件实测。
