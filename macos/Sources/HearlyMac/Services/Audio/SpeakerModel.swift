import Foundation
import SherpaOnnx

/// Acoustic checks complement (but never replace) the on-device phrase recognizer.
/// Audible energy by itself is not proof of speech or of a speaker's identity.
enum EnrollmentAudioQuality {
    static let sampleRate = 16000
    static let minimumAudibleSeconds = 2.0

    static func validatedSamples(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else {
            throw HearlyFailure.message("The microphone returned invalid audio. Please record again.")
        }
        let clipped = samples.reduce(0) { $0 + (abs($1) >= 0.98 ? 1 : 0) }
        guard Double(clipped) / Double(samples.count) <= 0.01 else {
            throw HearlyFailure.message("Your microphone is clipping. Move a little farther away or lower its input level, then try again.")
        }
        let frameLength = 320 // 20 ms; do not count an entire silent recording from one loud click.
        var audibleSamples = 0
        var firstAudible: Int?
        var lastAudible = 0
        for start in stride(from: 0, to: samples.count, by: frameLength) {
            let end = min(samples.count, start + frameLength)
            let meanSquare = samples[start..<end].reduce(Float(0)) { $0 + $1 * $1 } / Float(end - start)
            if meanSquare > 0.008 * 0.008 {
                audibleSamples += end - start
                if firstAudible == nil { firstAudible = start }
                lastAudible = end
            }
        }
        guard Double(audibleSamples) / Double(sampleRate) >= minimumAudibleSeconds, let firstAudible else {
            throw HearlyFailure.message("We need at least two seconds of clear, audible speech. Say the whole phrase naturally and try again.")
        }
        let padding = sampleRate / 10
        let trimmed = Array(samples[max(0, firstAudible - padding)..<min(samples.count, lastAudible + padding)])
        let rms = sqrt(trimmed.reduce(Float(0)) { $0 + $1 * $1 } / Float(trimmed.count))
        guard rms < 0.45 else {
            throw HearlyFailure.message("The recording is too loud. Lower the microphone input level and record again.")
        }
        return trimmed
    }
}

/// Used only on the audio worker queue, never in the hardware callback.
final class SpeakerModel {
    static let identifier = "campplus-zh-en-16k-advanced-v1"
    static let filename = "speaker-multilingual.onnx"
    private let extractor: OpaquePointer
    private let denoiser: OpaquePointer
    let dimensions: Int

    init(modelRoot: URL? = nil, speakerFilename: String = SpeakerModel.filename) throws {
        let root = modelRoot ?? Bundle.main.resourceURL?.appendingPathComponent("Models") ?? URL(fileURLWithPath: "Resources/Models")
        let speaker = root.appendingPathComponent(speakerFilename).path
        let noise = root.appendingPathComponent("denoiser.onnx").path
        guard FileManager.default.fileExists(atPath: speaker), FileManager.default.fileExists(atPath: noise) else { throw HearlyFailure.message("Hearly's voice models are missing. Rebuild the complete app bundle.") }
        let result = speaker.withCString { model in "cpu".withCString { provider in
            var config = SherpaOnnxSpeakerEmbeddingExtractorConfig(model: model, num_threads: 1, debug: 0, provider: provider)
            return SherpaOnnxCreateSpeakerEmbeddingExtractor(&config)
        } }
        guard let result else { throw HearlyFailure.message("The speaker recognition model could not load.") }
        extractor = result
        dimensions = Int(SherpaOnnxSpeakerEmbeddingExtractorDim(result))
        let cleaner = noise.withCString { model in "cpu".withCString { provider in
            var config = SherpaOnnxOnlineSpeechDenoiserConfig()
            config.model.gtcrn.model = model
            config.model.num_threads = 1
            config.model.provider = provider
            return SherpaOnnxCreateOnlineSpeechDenoiser(&config)
        } }
        guard let cleaner else {
            SherpaOnnxDestroySpeakerEmbeddingExtractor(result)
            throw HearlyFailure.message("The noise reduction model could not load.")
        }
        denoiser = cleaner
    }
    deinit {
        SherpaOnnxDestroySpeakerEmbeddingExtractor(extractor)
        SherpaOnnxDestroyOnlineSpeechDenoiser(denoiser)
    }
    func embedding(_ samples: [Float]) throws -> [Float] {
        guard samples.count >= 24000, samples.allSatisfy({ $0.isFinite }),
              let stream = SherpaOnnxSpeakerEmbeddingExtractorCreateStream(extractor) else { throw HearlyFailure.message("Record at least two seconds of clear speech.") }
        defer { SherpaOnnxDestroyOnlineStream(stream) }
        samples.withUnsafeBufferPointer { SherpaOnnxOnlineStreamAcceptWaveform(stream, 16000, $0.baseAddress, Int32($0.count)) }
        SherpaOnnxOnlineStreamInputFinished(stream)
        guard SherpaOnnxSpeakerEmbeddingExtractorIsReady(extractor, stream) != 0,
              let values = SherpaOnnxSpeakerEmbeddingExtractorComputeEmbedding(extractor, stream) else { throw HearlyFailure.message("Could not recognize speech in this recording. Try again in a quieter place.") }
        defer { SherpaOnnxSpeakerEmbeddingExtractorDestroyEmbedding(values) }
        let embedding = Self.normalized(Array(UnsafeBufferPointer(start: values, count: dimensions)))
        guard embedding.count == dimensions, !embedding.isEmpty else { throw HearlyFailure.message("The recording did not produce a valid voice profile. Please record it again.") }
        return embedding
    }
    func clean(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else { return [] }
        let result = samples.withUnsafeBufferPointer { SherpaOnnxOnlineSpeechDenoiserRun(denoiser, $0.baseAddress, Int32($0.count), 16000) }
        return copyDenoisedAudio(result)
    }
    /// For finite recordings/tests only. Live sessions stop without transmitting a buffered tail.
    func flushDenoiser() -> [Float] {
        copyDenoisedAudio(SherpaOnnxOnlineSpeechDenoiserFlush(denoiser))
    }
    func resetDenoiser() { SherpaOnnxOnlineSpeechDenoiserReset(denoiser) }

    private func copyDenoisedAudio(_ result: UnsafePointer<SherpaOnnxDenoisedAudio>?) -> [Float] {
        guard let result else { return [] }
        defer { SherpaOnnxDestroyDenoisedAudio(result) }
        guard result.pointee.n > 0, let samples = result.pointee.samples else { return [] }
        let values = Array(UnsafeBufferPointer(start: samples, count: Int(result.pointee.n)))
        guard result.pointee.sample_rate == 16000, values.allSatisfy({ $0.isFinite }) else { return [] }
        return values
    }
    static func normalized(_ values: [Float]) -> [Float] {
        let magnitude = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard magnitude.isFinite, magnitude > 0 else { return [] }
        return values.map { $0 / magnitude }
    }
    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
