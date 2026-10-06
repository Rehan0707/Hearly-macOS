import AVFoundation
import Speech

/// Apple speech-to-text only. SpeechAnalyzer is preferred on macOS 26+;
/// the compatibility path explicitly prohibits server recognition.
@MainActor
final class TranscriptService {
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private var backend: (any OnDeviceSpeechSession)?
    private var generation = UUID()

    func start() async throws {
        stop()
        let token = generation
        var modernFailure: String?
        if #available(macOS 26, *), SpeechTranscriber.isAvailable {
            let modern = AnalyzerSpeechSession()
            attach(modern, token: token)
            do {
                try await modern.start()
                guard generation == token, !Task.isCancelled else { modern.stop(); throw CancellationError() }
                onStatus?("Apple SpeechAnalyzer · on device")
                return
            } catch is CancellationError { throw CancellationError() }
            catch { modern.stop(); modernFailure = error.localizedDescription }
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        let legacy = LegacySpeechSession()
        attach(legacy, token: token)
        do {
            try await legacy.start()
            guard generation == token, !Task.isCancelled else { legacy.stop(); throw CancellationError() }
            onStatus?("Apple Speech Recognition · on device")
        } catch {
            legacy.stop()
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            backend = nil
            if let modernFailure {
                throw HearlyFailure.message("Apple's on-device speech model is not ready. \(modernFailure) Compatibility recognition: \(error.localizedDescription)")
            }
            throw error
        }
    }

    func append(_ samples: [Float]) { backend?.append(samples) }

    func stop() {
        generation = UUID()
        backend?.stop()
        backend = nil
    }

    private func attach(_ session: any OnDeviceSpeechSession, token: UUID) {
        backend = session
        session.onText = { [weak self] text in
            guard let self, self.generation == token else { return }
            self.onText?(text)
        }
        session.onStatus = { [weak self] text in
            guard let self, self.generation == token else { return }
            self.onStatus?(text)
        }
        session.onError = { [weak self] message in
            guard let self, self.generation == token else { return }
            self.stop()
            self.onError?(message)
        }
    }
}

@MainActor
private protocol OnDeviceSpeechSession: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start() async throws
    func append(_ samples: [Float])
    func stop()
}

private func speechBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
    guard !samples.isEmpty, samples.allSatisfy(\.isFinite),
          let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
          let channel = buffer.floatChannelData else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { channel[0].update(from: $0.baseAddress!, count: samples.count) }
    return buffer
}

@available(macOS 26, *)
@MainActor
private final class AnalyzerSpeechSession: OnDeviceSpeechSession {
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var generation = UUID()
    private var convert: ((AVAudioPCMBuffer) throws -> [AnalyzerInput])?
    private var segments: [(start: Double, end: Double, text: String)] = []

    func start() async throws {
        let token = generation
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw HearlyFailure.message("This Mac does not support Apple's on-device English transcription model.")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        guard status == .installed else {
            throw HearlyFailure.message("Install English on-device speech assets in macOS System Settings, then retry. Hearly does not download models or send audio to a server.")
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw HearlyFailure.message("Apple's speech model did not provide a compatible audio format.")
        }
        if #available(macOS 27, *) {
            let converter = AnalyzerInputConverter(analyzerFormat: format)
            convert = { try converter.convert($0, at: nil) }
        } else {
            let input = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            guard let converter = AVAudioConverter(from: input, to: format) else {
                throw HearlyFailure.message("Cannot convert microphone audio for Apple's speech model.")
            }
            convert = { buffer in
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / input.sampleRate)) + 64
                guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
                var supplied = false
                var error: NSError?
                let result = converter.convert(to: output, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                if let error { throw error }
                guard result != .error, output.frameLength > 0 else { return [] }
                return [AnalyzerInput(buffer: output)]
            }
        }
        let session = SpeechAnalyzer(modules: [transcriber])
        analyzer = session
        try await session.prepareToAnalyze(in: format)
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(120))
        self.continuation = continuation
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    guard start.isFinite, end.isFinite else { continue }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Volatile results replace text for their audio range.
                    self.segments.removeAll { abs($0.start - start) < 0.001 || ($0.start < end && $0.end > start) }
                    if !text.isEmpty { self.segments.append((start, end, text)) }
                    self.segments.sort { $0.start < $1.start }
                    self.onText?(self.segments.map(\.text).joined(separator: " "))
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail("On-device transcription stopped: " + error.localizedDescription)
            }
        }
        try await session.start(inputSequence: stream)
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
    }

    func append(_ samples: [Float]) {
        guard let convert, let continuation, let buffer = speechBuffer(samples) else { return }
        do {
            for input in try convert(buffer) {
                if case .dropped = continuation.yield(input) {
                    fail("On-device speech recognition could not keep up. Stop other intensive work and retry the recording.")
                    return
                }
            }
        } catch { fail("Cannot process speech audio: " + error.localizedDescription) }
    }

    func stop() {
        generation = UUID()
        continuation?.finish()
        continuation = nil
        resultTask?.cancel()
        resultTask = nil
        convert = nil
        segments = []
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
    }

    private func fail(_ message: String) { stop(); onError?(message) }
}

@MainActor
private final class LegacySpeechSession: OnDeviceSpeechSession {
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var requestGeneration = UUID()
    private var committed = ""
    private var partial = ""
    private var rollover: Task<Void, Never>?

    func start() async throws {
        let token = generation
        let permission: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        guard permission == .authorized else {
            throw HearlyFailure.message("Allow Speech Recognition for Hearly in System Settings → Privacy & Security → Speech Recognition.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw HearlyFailure.message("On-device English recognition is unavailable. Download English Dictation in System Settings → Keyboard, then retry. Hearly will not use cloud recognition.")
        }
        self.recognizer = recognizer
        startRequest()
    }

    private func startRequest() {
        guard let recognizer else { return }
        let token = generation
        let requestToken = UUID()
        requestGeneration = requestToken
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["Hearly"]
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == token, self.requestGeneration == requestToken else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    self.onText?(self.joinedText)
                    if result.isFinal { self.restartRequest(); return }
                }
                if let error {
                    self.stop()
                    self.onError?("On-device speech recognition stopped: " + error.localizedDescription)
                }
            }
        }
        // Compatibility tasks may end near one minute. Reopen before that
        // limit while preserving previously recognized text.
        rollover = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000_000)
            guard !Task.isCancelled, let self, self.generation == token, self.requestGeneration == requestToken else { return }
            self.restartRequest()
        }
    }

    private var joinedText: String { [committed, partial].filter { !$0.isEmpty }.joined(separator: " ") }

    private func restartRequest() {
        committed = joinedText
        partial = ""
        requestGeneration = UUID()
        rollover?.cancel()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        startRequest()
    }

    func append(_ samples: [Float]) {
        guard let request, let buffer = speechBuffer(samples) else { return }
        request.append(buffer)
    }

    func stop() {
        generation = UUID()
        requestGeneration = UUID()
        rollover?.cancel()
        rollover = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recognizer = nil
        committed = ""
        partial = ""
    }
}
