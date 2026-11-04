# 雨滴与 app 图标

v0.5.2 公开测试版。

## 原模型与图标

直接导出用户提供的 `raindrop-avatar/src/drop-model.js`：同一份 5 mesh、9184 顶点的几何、眼睛和高光，默认粉色 `#FFF2F6`。`Resources/Avatar/raindrop.json` 保存源文件 SHA256，Three.js MIT 声明随资源打包。运行时由原生 SceneKit 渲染。

图标使用已确认的 **D / Mist（雾粉灰）**。正式源图为 `Resources/AppIcon.png`，`Resources/AppIcon.icns` 包含标准与 Retina 尺寸并随 app 打包。更新源图后运行 `scripts/build-app-icon.sh`。

更新模型：`node scripts/export-raindrop.mjs [avatar目录]`，该更新脚本需要原目录已安装的 Three.js。预生成资源包含在仓库中，正常构建无需执行导出脚本。

## 歌词栏

设置 → 雨滴：

- 显示开关，默认关闭，实时生效并自动保存
- 静止：保持静止，偶尔眨眼
- 摇摆：播放时循环摇摆，暂停停止；不是节拍检测
- 音频律动：由当前 Spotify / Apple Music 输出音频的 RMS 包络驱动弹跳与挤压；不是精确 BPM 检测

雨滴在两行文字左边独占空间。关闭后释放场景；隐藏窗口不更新动画。系统 Reduce Motion 会关闭动态效果和音频采集。修改外观预设不会关闭雨滴。旧版 appearance JSON 缺失新增字段时保留原字体、配色和其他设置。

## 可选音频连接

只有用户主动点击“连接音乐音频”后才建立 tap，重启 app 后也需重新点击。要求 macOS 14.2+；macOS 13 保留安静与摇摆两种模式。选择当前播放器的 HAL 输出进程及其同 bundle 前缀辅助进程，不回退到全系统录制；私有、unmuted tap 保持原播放。只有 tap 加入私有 aggregate，不加入麦克风设备。

音频只进入实时 C RMS callback，再通过 atomic float 给 20 Hz UI 读取。不写磁盘、不上传。系统会处理音频录制授权。暂停、关闭雨滴、切换动作、隐藏歌词或退出 app 会停止采集。连接失败会显示状态并等待用户重试，全零样本显示“等待播放器音频”，不推断为拒绝授权。

原理与官方 API 来源见 [音频可行性调查](raindrop-audio-feasibility.md)。真实 Spotify / Music 样本、用户授权与 ad hoc 签名下的权限保留仍待用户主动开启后实测。

## 验证

- Universal arm64 / x86_64 构建与 ad hoc 签名校验
- `scripts/check.sh`：42 scenarios，0 failures
- `scripts/check-appearance.sh`：原生控件到真实歌词窗口、显示开关、5 mesh 加载、文字避让、暂停 / 静音 / Reduce Motion、旧版迁移与新进程保存恢复
- `scripts/check-pet-audio.sh`：合成立体声 RMS、静音、NaN/Infinity；不启动采集
- [设置页](images/settings-pet.png)：原生设置页导出
- [动画示例](images/lyrics-pet-demo.gif)：实际 LyricsView 与原模型渲染的摇摆示例，不来自真实音乐音频

当前仅在本机 Apple Silicon 实测 UI。x86_64 已编译，未在 Intel 硬件运行。
