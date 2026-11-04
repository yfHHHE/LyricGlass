# 雨滴伙伴：音频律动可行性

调查日期：2026-11-04。范围：公开 Apple API 与本机 macOS SDK；未启动音频采集，未请求系统权限。

## 结论

可以做真正由当前播放器音频驱动的动画。建议先提供“轻轻摇摆”，再提供用户主动开启的“随音乐律动”。后者监听目标播放器的输出样本，提取响度与瞬态，驱动雨滴的弹跳和挤压；应称为音频律动，不能承诺准确识别每首歌的 BPM 或每一拍。

Core Audio process tap 的创建与销毁 API 从 **macOS 14.2** 开始可用。现有 macOS 13 最低要求可保留，用 availability guard 隔开；旧系统保留静态与播放状态动画。Apple 的示例明确采用 tap → HAL aggregate device → 音频读取的路径。[Apple 官方示例](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)、本机 SDK `AudioHardwareTapping.h:34–54`

## API 与选择播放器

最小链路：

1. 根据当前自动识别的播放器找到进程 PID，使用 `kAudioHardwarePropertyTranslatePIDToProcessObject` 读取其 HAL `AudioObjectID`。PID 是 `pid_t` qualifier。即便调用返回成功，也必须检查结果不为 `kAudioObjectUnknown`；不存在的 PID 不一定产生错误。本机 SDK `AudioHardware.h:589–595`
2. `CATapDescription(stereoMixdownOfProcesses: ids)` 指定目标进程；设置 `isPrivate = true`、`muteBehavior = .unmuted`。这样不会故意静音正常扬声器播放。不要用 global tap 作为目标匹配失败的回退。[CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription)、本机 SDK `CATapDescription.h:20–80, 148–179`
3. 创建 tap，读取 `kAudioTapPropertyUID` 和 `kAudioTapPropertyFormat`。后者为实际 `AudioStreamBasicDescription`，不能未经验证就把缓冲区当成 Float32。本机 SDK `AudioHardware.h:2003–2022`
4. 创建私有 aggregate：`kAudioAggregateDeviceIsPrivateKey: true`，`kAudioAggregateDeviceTapListKey` 内含 `kAudioSubTapUIDKey`。可设 drift compensation。仅加入 tap 即可避免混入设备麦克风输入；不要把硬件输入设备也加入 aggregate。本机 SDK `AudioHardware.h:1600–1640, 1856–1887`
5. 注册 IOProc，用户主动开启后 `AudioDeviceStart`；关闭时依次 stop、destroy IOProc、destroy aggregate、destroy tap。所有失败路径也应清理已创建对象。[IOProc 官方 API](https://developer.apple.com/documentation/coreaudio/audiodevicecreateioprocidwithblock(_:_:_:_:))

Spotify 等应用可能通过辅助进程输出声音，因此主应用 PID 无 HAL 对象时，不应立即断言权限被拒。可枚举 `kAudioHardwarePropertyProcessObjectList`，结合 `kAudioProcessPropertyPID`、`kAudioProcessPropertyBundleID` 和 `kAudioProcessPropertyIsRunningOutput` 检查明确属于该播放器的进程。实际辅助进程标识必须运行时验证，不能泛选所有正在输出的进程。[AudioHardwareProcess](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess)、本机 SDK `AudioHardware.h:586–595, 1948–1978`

当前 SDK 的 `CATapDescription.bundleIDs` 和 `isProcessRestoreEnabled` 是 **macOS 26** 新属性。若支持 14.2，首版使用 process IDs，在播放器切换、退出重启、HAL service restart 后重新解析并重建 tap。本机 SDK `CATapDescription.h:145–172`、`AudioHardware.h:574–579`

## 权限与界面

Info.plist 必须包含 `NSAudioCaptureUsageDescription`，例如“让雨滴根据当前播放器的音乐律动，仅在本机分析音量，不保存音频”。Apple 文档说明，第一次从带有 tap 的 aggregate 开始录制时，系统会请求系统音频录制权限。因此默认关闭真实音频模式；仅在用户明确选择后启动。[权限说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription)、[触发时机](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)

该路径读取应用输出，不需要把麦克风输入加入设备。当前 LyricGlass entitlement 只有 Apple Events；本次未验证 ad hoc 签名下的 TCC 持久性。不能凭静态 API 可用性宣称这台机器已经授权或能收到 Spotify/Apple Music 样本。

没有找到可依赖的公开 Core Audio tap 授权预检 API。API 错误、无回调、全零样本分别展示“无法启动音频律动”“等待播放器音频”等状态。全零也可能是静音、暂停、源进程不对或不可采集的内容，不能单凭它断言拒绝授权。失败时保留轻摇模式，且不自动扩大到全部系统音频。

## 动画与线程建议

这是实现建议，而非 Apple 对节拍检测的保证：对 PCM 分块算 RMS / peak，以约 100–250 ms 平滑包络驱动缩放；高于短期平均能量的正向增量作为 onset 候选，设置约 180 ms refractory period，避免一串颤动。音量接近零时回到静止；暂停时清空包络；尊重系统 Reduce Motion。

IOProc 中避免 AppKit、日志、文件写入、网络、分配和 UI dispatch。Apple 明确建议 IOProc 使用 C 以保证 realtime safety；最稳妥的是小型 C callback 计算预分配状态，UI 按现有 20 Hz render timer 读取。不要让 Swift 闭包里不断创建数组或锁住主线程。[Apple realtime 提醒](https://developer.apple.com/documentation/coreaudio/audiohardwaredevice/start(ioprocid:))

## 验证边界

已核实官方文档和 SDK API。已准备只 typecheck、不调用的 Swift 草稿，覆盖 PID qualifier、私有 tap、unmuted、aggregate tap 字典和 IOProc 签名。真实用户授权、Spotify 辅助进程选择、Apple Music 可读性、设备切换和签名权限持久性仍需单独验证。

建议最小交付：雨滴显示开关 + 静态/轻摇两种模式先完成；真实音频模式需有明确权限说明、可见失败状态和非录音单元测试后再开放。不要把固定循环摇摆标成“跟拍”。
