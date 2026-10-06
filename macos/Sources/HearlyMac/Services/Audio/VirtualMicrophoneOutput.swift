import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// A normal Core Audio output connection keeps the app sandbox intact. The HAL
/// loopback exposes this output as Hearly Microphone's input to meeting clients.
final class VirtualMicrophoneOutput: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private let pending = DispatchSemaphore(value: 3)
    private let lock = NSLock()
    private var stopped = false

    init() throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            throw HearlyFailure.message("Core Audio could not list audio devices.")
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr,
              let device = devices.first(where: { Self.uid($0) == "live.hearely.virtual-mic" }) else {
            throw HearlyFailure.message("Install the Hearly Microphone driver before starting a listening session.")
        }
        var outputAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var outputSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &outputAddress, 0, nil, &outputSize) == noErr, outputSize > 0 else {
            throw HearlyFailure.message("The installed Hearly driver is an older version. Install the updated loopback driver and restart Core Audio.")
        }
        guard let unit = engine.outputNode.audioUnit else { throw HearlyFailure.message("The virtual microphone output could not initialize.") }
        var selected = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selected, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw HearlyFailure.message("Could not connect to Hearly Microphone (\(status)).") }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.play()
    }

    static func uid(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Called by the serial model worker; never grows an unbounded playback queue.
    @discardableResult
    func write(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty, pending.wait(timeout: .now()) == .success else { return false }
        lock.lock(); defer { lock.unlock() }
        guard !stopped,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { pending.signal(); return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [pending] _ in pending.signal() }
        return true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        player.stop()
        engine.stop()
    }
    deinit { stop() }
}
