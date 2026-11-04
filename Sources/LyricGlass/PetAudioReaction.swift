import AppKit
import CoreAudio
import PetAudio

/// A private tap of the selected music app only. No microphone, files or network.
final class PetAudioReaction {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private let meter = LGLevelMeterCreate()!
    private var target: [AudioObjectID] = []
    private var lastAttempt = -Double.infinity
    private var envelope = 0.0
    private var failed = false
    private(set) var status = "点击「连接音乐音频」后开始"
    private(set) var active = false

    deinit { stop(); LGLevelMeterDestroy(meter) }
    func stop() {
        if aggregate != 0 {
            if let io { AudioDeviceStop(aggregate, io); AudioDeviceDestroyIOProcID(aggregate, io) }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if #available(macOS 14.2, *), tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        aggregate = 0; tap = 0; io = nil; target = []; active = false; envelope = 0
    }

    func pulse() -> Double {
        let level = active ? Double(LGLevelMeterRead(meter)) : 0
        let desired = min(1, max(0, (sqrt(level) - 0.035) * 2.4))
        envelope += (desired - envelope) * (desired > envelope ? 0.7 : 0.22)
        if active { status = level > 0.0001 ? "音乐音频已连接 · 根据强弱起伏" : "等待播放器音频 · 暂无可读声音" }
        return envelope
    }

    func retry() { lastAttempt = -.infinity; failed = false; stop() }
    func follow(bundleID: String, at time: Double) {
        guard #available(macOS 14.2, *) else { status = "音频律动需要 macOS 14.2 或更新版本"; return }
        guard !failed, time - lastAttempt >= 2 else { return }
        lastAttempt = time
        do {
            let processes = try outputProcesses(bundleID: bundleID)
            guard !processes.isEmpty else {
                stop(); status = "等待播放器输出音频"; return
            }
            if active && target == processes { return }
            stop()
            let description = CATapDescription(stereoMixdownOfProcesses: processes)
            description.name = "LyricGlass · 雨滴音乐律动"
            description.isPrivate = true; description.muteBehavior = .unmuted
            try checked(AudioHardwareCreateProcessTap(description, &tap))
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.size(ofValue: format))
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            try checked(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
            guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else { throw CocoaError(.featureUnsupported) }
            let configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "LyricGlass RainDrop",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                 kAudioSubTapDriftCompensationKey: true]]
            ]
            try checked(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate))
            try checked(AudioDeviceCreateIOProcID(aggregate, LGLevelMeterIOProc, UnsafeMutableRawPointer(meter), &io))
            try checked(AudioDeviceStart(aggregate, io))
            target = processes; active = true
            status = "等待播放器音频 · 暂无可读声音"
        } catch {
            stop(); failed = true; status = "无法连接音乐音频 · 可重试或改为摇摆"
            // Do not infer a permission denial from silence or generic HAL errors.
            NSLog("RainDrop audio tap setup: %@", error.localizedDescription)
        }
    }

    private func checked(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    @available(macOS 14.2, *)
    private func outputProcesses(bundleID: String) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try checked(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !objects.isEmpty else { return [] }
        try objects.withUnsafeMutableBytes { bytes in
            try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!))
        }
        return objects.filter { object in
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout.size(ofValue: name))
            var property = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &property, 0, nil, &nameSize, &name) == noErr else { return false }
            guard let name else { return false }
            let id = name.takeRetainedValue() as String
            guard id == bundleID || id.hasPrefix(bundleID + ".") else { return false }
            property.mSelector = kAudioProcessPropertyIsRunningOutput
            var running: UInt32 = 0; var runningSize = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(object, &property, 0, nil, &runningSize, &running) == noErr && running != 0
        }.sorted()
    }
}
