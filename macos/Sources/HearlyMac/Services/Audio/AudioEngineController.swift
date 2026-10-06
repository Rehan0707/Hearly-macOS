import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Darwin

@MainActor
final class AudioEngineController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var meterLevel: Float = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var speakerScore: Float = 0
    @Published private(set) var voicedSeconds: Double = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var droppedFrames = 0
    @Published private(set) var isAuditionActive = false
    @Published private(set) var auditionFeed: AuditionFeed = .filtered
    @Published private(set) var auditionVolume: Float = 0.85
    var voiceIsolationEnabled = true
    var onFilteredSamples: (([Float]) -> Void)?
    /// Raw mono 16 kHz capture PCM for on-device phrase recognition, delivered on MainActor.
    /// Enrollment/verification never forwards this audio to the virtual microphone.
    var onCaptureSamples: (([Float]) -> Void)?
    private let engine = AVAudioEngine()
    private let worker = DispatchQueue(label: "live.hearly.audio-worker", qos: .userInitiated)
    private let capacity = DispatchSemaphore(value: 6)
    private var pipeline: AudioPipeline?
    private var generation = UUID()
    private var tapInstalled = false

    func setAuditionActive(_ active: Bool) {
        isAuditionActive = active
        pipeline?.setAuditionActive(active)
    }

    func setAuditionFeed(_ feed: AuditionFeed) {
        auditionFeed = feed
        pipeline?.setAuditionFeed(feed)
    }

    func setAuditionVolume(_ volume: Float) {
        auditionVolume = volume
        pipeline?.setAuditionVolume(volume)
    }

    func switchInputDevice(to newDeviceID: UInt32?, profile: VoiceProfile? = nil, threshold: Float = 0.55) async {
        guard isRunning else { return }
        let wasCapturing = isCapturing
        let wasMonitoring = isMonitoring
        stop()
        await start(
            inputDeviceID: newDeviceID,
            profile: profile,
            capture: wasCapturing,
            threshold: threshold,
            monitorOnly: wasMonitoring
        )
    }

    func start(inputDeviceID: UInt32?, profile: VoiceProfile? = nil, capture: Bool = false, threshold: Float = 0.55, monitorOnly: Bool = false) async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        let token = UUID()
        generation = token
        defer { if generation == token { isStarting = false } }
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == token else { return }
        guard permitted else { errorMessage = "Allow Microphone access in System Settings → Privacy & Security → Microphone."; return }
        do {
            let input = engine.inputNode
            // Never feed Hearly's virtual input back into itself when it is the
            // system default microphone. An explicit physical selection is required.
            if inputDeviceID == nil {
                var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var defaultInput = AudioDeviceID(0)
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultInput) == noErr,
                   VirtualMicrophoneOutput.uid(defaultInput) == "live.hearely.virtual-mic" {
                    throw HearlyFailure.message("Choose your physical microphone in Audio Setup. Hearly Microphone is the processed output and cannot be its own input.")
                }
            }
            if let inputDeviceID, VirtualMicrophoneOutput.uid(inputDeviceID) == "live.hearely.virtual-mic" {
                throw HearlyFailure.message("Select a physical microphone, not Hearly Microphone.")
            }
            if let id = inputDeviceID, let unit = input.audioUnit {
                var deviceID = AudioDeviceID(id)
                let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
                guard result == noErr else { throw HearlyFailure.message("Could not select this microphone (\(result)).") }
            }
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { throw HearlyFailure.message("No microphone is available.") }
            let isAudition = isAuditionActive
            let feed = auditionFeed
            let vol = auditionVolume
            let newPipeline: AudioPipeline = try await withCheckedThrowingContinuation { continuation in
                worker.async {
                    do {
                        continuation.resume(returning: try AudioPipeline(
                            format: format,
                            capture: capture,
                            profile: profile,
                            threshold: threshold,
                            monitorOnly: monitorOnly,
                            auditionActive: isAudition,
                            auditionFeed: feed,
                            auditionVolume: vol
                        ))
                    }
                    catch { continuation.resume(throwing: error) }
                }
            }
            guard generation == token else { return }
            pipeline = newPipeline
            voicedSeconds = 0
            droppedFrames = 0
            isCapturing = capture
            isMonitoring = monitorOnly
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, worker, capacity] buffer, _ in
                guard capacity.wait(timeout: .now()) == .success else {
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.droppedFrames += 1
                    }
                    return
                }
                guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
                      let from = buffer.floatChannelData, let to = copy.floatChannelData else { capacity.signal(); return }
                copy.frameLength = buffer.frameLength
                for channel in 0..<Int(format.channelCount) {
                    to[channel].update(from: from[channel], count: Int(buffer.frameLength))
                }
                worker.async {
                    defer { capacity.signal() }
                    let result = newPipeline.process(copy)
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.meterLevel = result.level
                        self.speakerScore = result.score
                        self.voicedSeconds = result.voicedSeconds
                        if capture { self.onCaptureSamples?(result.samples) }
                        else if !monitorOnly { self.onFilteredSamples?(result.samples) }
                    }
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            guard generation == token else { return }
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        generation = UUID()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        isRunning = false
        isStarting = false
        isCapturing = false
        isMonitoring = false
        meterLevel = 0
        let old = pipeline
        old?.invalidate()
        pipeline = nil
        worker.async { old?.closeRoute() }
    }

    func finishCapture() async throws -> [Float] {
        guard let captured = pipeline, isCapturing else { throw HearlyFailure.message("Start a recording first.") }
        stop()
        return try await withCheckedThrowingContinuation { continuation in
            worker.async {
                do { continuation.resume(returning: try captured.enrollmentEmbedding()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func clearError() { errorMessage = nil }
}

/// All mutable state belongs to the serial worker. Hardware callbacks only copy a bounded amount of PCM.
private final class AudioPipeline: @unchecked Sendable {
    struct Result { let samples: [Float]; let level: Float; let score: Float; let voicedSeconds: Double }
    private let model: SpeakerModel
    private let converter: AVAudioConverter
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private let capture: Bool
    private let monitorOnly: Bool
    private let profile: VoiceProfile?
    private let threshold: Float
    private var recording: [Float] = []
    private var rolling: [Float] = []
    private var decisionFrames = 0
    private var score: Float = 0
    private var voiced: Double = 0
    private var gain: Float = 0
    private var route: VirtualMicrophoneOutput?
    private let auditionPlayer = AuditionPlayer()
    private var auditionActive: Bool
    private var auditionFeed: AuditionFeed
    private let lifecycleLock = NSLock()
    private var isActive = true

    init(format: AVAudioFormat, capture: Bool, profile: VoiceProfile?, threshold: Float, monitorOnly: Bool = false, auditionActive: Bool = false, auditionFeed: AuditionFeed = .filtered, auditionVolume: Float = 0.85) throws {
        model = try SpeakerModel()
        guard let converter = AVAudioConverter(from: format, to: self.format) else { throw HearlyFailure.message("This microphone format is unsupported.") }
        self.converter = converter
        self.capture = capture
        self.monitorOnly = monitorOnly
        self.profile = profile
        self.threshold = threshold
        self.auditionActive = auditionActive
        self.auditionFeed = auditionFeed
        self.auditionPlayer.volume = auditionVolume
        if auditionActive {
            try? auditionPlayer.start()
        }
        if !capture && !monitorOnly {
            guard let profile, profile.model == SpeakerModel.identifier, profile.embedding.count == model.dimensions else { throw HearlyFailure.message("Enroll your voice before starting Hearly.") }
            route = try VirtualMicrophoneOutput()
        }
    }

    deinit { closeRoute() }
    func closeRoute() {
        route?.stop()
        route = nil
        auditionPlayer.stop()
    }
    /// Cancellation can arrive on the main thread while PCM work is queued.
    func invalidate() {
        lifecycleLock.lock(); isActive = false; lifecycleLock.unlock()
        route?.stop()
        auditionPlayer.stop()
    }
    private var active: Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return isActive
    }

    func setAuditionActive(_ active: Bool) {
        auditionActive = active
        if active {
            try? auditionPlayer.start()
        } else {
            auditionPlayer.stop()
        }
    }

    func setAuditionFeed(_ feed: AuditionFeed) {
        auditionFeed = feed
    }

    func setAuditionVolume(_ volume: Float) {
        auditionPlayer.volume = volume
    }

    func process(_ input: AVAudioPCMBuffer) -> Result {
        guard active else { return Result(samples: [], level: 0, score: 0, voicedSeconds: voiced) }
        let count = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate) + 16)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return Result(samples: [], level: 0, score: score, voicedSeconds: voiced) }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard conversionError == nil, let values = output.floatChannelData else { return Result(samples: [], level: 0, score: score, voicedSeconds: voiced) }
        let raw = Array(UnsafeBufferPointer(start: values[0], count: Int(output.frameLength)))
        guard raw.allSatisfy({ $0.isFinite }) else { return Result(samples: [], level: 0, score: 0, voicedSeconds: voiced) }
        let rms = sqrt(raw.reduce(0) { $0 + $1 * $1 } / Float(max(1, raw.count)))
        if rms > 0.008 { voiced += Double(raw.count) / 16000 }
        if monitorOnly {
            if auditionActive {
                auditionPlayer.write(raw)
            }
            return Result(samples: raw, level: min(1, rms * 8), score: 0, voicedSeconds: voiced)
        }
        if capture {
            if recording.count < 16000 * 30 { recording.append(contentsOf: raw) }
            return Result(samples: raw, level: min(1, rms * 8), score: 0, voicedSeconds: voiced)
        }
        let cleaned = model.clean(raw)
        rolling.append(contentsOf: cleaned)
        if rolling.count > 32000 { rolling.removeFirst(rolling.count - 32000) }
        decisionFrames += cleaned.count
        if rolling.count >= 24000, decisionFrames >= 8000 {
            decisionFrames = 0
            score = (try? SpeakerModel.similarity(model.embedding(rolling), profile?.embedding ?? [])) ?? 0
        }
        let target: Float = score >= threshold && rms > 0.004 ? 1 : 0
        var filtered = cleaned
        for i in filtered.indices {
            gain += (target - gain) * (target > gain ? 0.015 : 0.03)
            filtered[i] *= gain
        }
        guard active else { return Result(samples: [], level: 0, score: 0, voicedSeconds: voiced) }
        route?.write(filtered)
        if auditionActive {
            auditionPlayer.write(auditionFeed == .filtered ? filtered : raw)
        }
        return Result(samples: filtered, level: min(1, rms * 8), score: score, voicedSeconds: voiced)
    }

    func enrollmentEmbedding() throws -> [Float] {
        try model.embedding(EnrollmentAudioQuality.validatedSamples(recording))
    }
}
