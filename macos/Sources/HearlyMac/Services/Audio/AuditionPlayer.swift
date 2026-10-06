import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AuditionFeed: String, CaseIterable, Identifiable {
    case filtered = "Filtered"
    case raw = "Raw Mic"

    var id: String { rawValue }
}

final class AuditionPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private let pending = DispatchSemaphore(value: 3)
    private let lock = NSLock()
    private var isPlaying = false
    private var stopped = false

    var volume: Float {
        get { player.volume }
        set { player.volume = max(0, min(1, newValue)) }
    }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = 0.85
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isPlaying else { return }
        stopped = false
        engine.prepare()
        try engine.start()
        player.play()
        isPlaying = true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isPlaying else { return }
        player.stop()
        engine.stop()
        isPlaying = false
        stopped = true
    }

    @discardableResult
    func write(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty, pending.wait(timeout: .now()) == .success else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard isPlaying, !stopped,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            pending.signal()
            return false
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [pending] _ in
            pending.signal()
        }
        return true
    }
}
