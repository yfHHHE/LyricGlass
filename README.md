# LyricGlass

Spotify 的 macOS 透明双行桌面歌词。当前一句高亮，下一句预览，放在桌面底部，工作时也能看到歌词。

**[下载最新测试版](https://github.com/yfHHHE/LyricGlass/releases)** · [首次运行说明](docs/首次运行.txt)

## 安装

要求 **macOS 13+、Spotify 桌面客户端**。安装包为 Universal，包含 Apple Silicon（arm64）和 Intel（x86_64）。当前界面为中文。

1. 在 [Releases](https://github.com/yfHHHE/LyricGlass/releases) 下载 `.dmg`，打开后把 `LyricGlass.app` 拖入 Applications；也可下载 ZIP 并解压
2. 打开 LyricGlass，允许读取 Spotify 的“自动化”权限
3. 在 Spotify 桌面端播放歌曲，歌词匹配后自动显示

**当前版本未使用 Apple Developer ID 签名，也未公证。** macOS 可能阻止首次打开。确认文件来自本项目 Release 后，先尝试打开一次，再到“系统设置 → 隐私与安全性”找到 LyricGlass，选择“仍要打开”。详见 [Apple 官方说明](https://support.apple.com/102445)。受组织管理的 Mac 可能不允许此操作。

下载使用不需要 Xcode、命令行工具、Spotify 开发者账号或 API key。

## 功能与操作

- 自动跟随 Spotify 的歌曲、暂停、继续、切歌与进度跳转
- 透明双行歌词，支持拖动、置顶、鼠标穿透和字号调整
- 鼠标悬停显示歌曲、进度与同步状态
- 右键歌词，或点击菜单栏气泡图标打开设置
- 歌词每次可提前/延后 0.5 秒，范围 ±15 秒，切歌归零
- 无匹配歌词时，支持为当前歌曲导入 UTF-8 `.lrc`

## 常见问题

**没有读取到 Spotify？**

确认使用桌面客户端并播放一首歌。若权限曾被拒绝，到“系统设置 → 隐私与安全性 → 自动化 → LyricGlass → Spotify”打开权限，再点歌词菜单里的“重试 Spotify 连接”。

**找不到歌词或显示服务繁忙？**

歌词来自 [LRCLIB](https://lrclib.net/docs)，并非直接获取 Spotify 内的歌词。覆盖度和时间轴质量因歌曲而异。服务繁忙时可重试；没有时间轴时不会伪造同步滚动，可导入本地 LRC。

**全屏或其他设备播放能用吗？**

当前只验证了本机 Spotify 桌面端；网页版、其他 Spotify Connect 设备、独占全屏窗口尚未验证。

**退出后为什么设置恢复默认？**

v0.1.0 的缓存、导入映射、位置、字体和偏移只保留在内存。

## 隐私与第三方服务

- 通过 Spotify 的 Apple events 属性读取当前歌曲、播放状态与进度，不读取账号凭据
- 向 `https://lrclib.net` 发送歌名、歌手、专辑与时长，用于匹配歌词
- 不上传音频、Spotify token、账号信息或导入的本地 LRC
- 没有项目自行添加的遥测或分析服务，不在磁盘保存歌词缓存
- 安装包不包含第三方歌词；第三方服务内容及权利归各自权利人

本项目独立于 Spotify，与 Spotify 无隶属关系。源码公开供查看，尚未指定开源许可证。

## 从源码构建

需要 macOS 和 Apple Command Line Tools / Swift 5.9+，没有外部 Swift 包依赖。

```sh
./run.command                  # 构建并打开本机构架版本
./run.command --demo           # 用自写歌词演示，不读取 Spotify、不请求网络
./scripts/check.sh             # 6 组核心回归，不访问网络
./scripts/build-app.sh --universal
./scripts/package-release.sh   # 生成 Universal DMG、ZIP 和 SHA256SUMS.txt
```

app 输出在 `dist/LyricGlass.app`。Release 包仅为本地 ad-hoc 签名，打包脚本不会自动申请证书或公证。

可选诊断：

```sh
dist/LyricGlass.app/Contents/MacOS/LyricGlass --check-lyrics
dist/LyricGlass.app/Contents/MacOS/LyricGlass --diagnose-spotify
```

`--check-lyrics` 仅查询固定公开测试曲的元数据与时间戳行数；`--diagnose-spotify` 在本地输出当前播放状态，权限可能记在宿主终端名下，以 app 实际运行的授权为准。

## 同步方式与验证范围

每 0.5 秒读取 Spotify，在两次采样间用 monotonic clock 推进；读数超过 2 秒未刷新则冻结。按歌名、歌手和时长匹配歌词，容许时长差 ±2 秒，保留 live/remix 等版本名，并做繁简归一。切歌时取消旧请求并校验歌曲身份，避免旧请求覆盖新歌。

核心回归覆盖时间戳与偏移、同时刻双语行、前奏/间奏、暂停与继续、前后跳转、过期读数冻结、版本匹配和播放时钟到歌词选择的组合场景。Spotify 实际播放同步已在 Apple Silicon 上验证；Intel 构建和其他 macOS 版本尚未完成硬件实测。
