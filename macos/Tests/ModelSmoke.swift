import Foundation
import AVFoundation
import SherpaOnnx

/// Small integration regression, not an accuracy benchmark. See Fixtures/README.md.
@main
struct ModelSmoke {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw HearlyFailure.message("FAIL: " + message) }
    }
    static func read(_ name: String) throws -> [Float] {
        let path = "Tests/Fixtures/\(name).wav"
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: source)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let converter = AVAudioConverter(from: source.format, to: format)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * 16000 / source.format.sampleRate + 100))!
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return source
        }
        if let error { throw error }
        let samples = Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
        guard let wave = SherpaOnnxReadWave(path) else { throw HearlyFailure.message("Could not independently decode \(path)") }
        defer { SherpaOnnxFreeWave(wave) }
        let native = Array(UnsafeBufferPointer(start: wave.pointee.samples, count: Int(wave.pointee.num_samples)))
        try require(wave.pointee.sample_rate == 16000 && native == samples, "AVFoundation PCM must match the independent WAV reader for \(name)")
        return samples
    }
    static func clean(_ samples: [Float], model: SpeakerModel) -> [Float] {
        model.resetDenoiser()
        var output: [Float] = []
        for index in stride(from: 0, to: samples.count, by: 1024) {
            output += model.clean(Array(samples[index..<min(samples.count, index + 1024)]))
        }
        output += model.flushDenoiser()
        return output
    }
    static func rms(_ samples: [Float]) -> Float {
        sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
    }
    static func main() {
        do { try run() }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let filename = CommandLine.arguments.dropFirst().first ?? SpeakerModel.filename
        let model = try SpeakerModel(modelRoot: root.appendingPathComponent("Resources/Models"), speakerFilename: filename)
        let reference = try model.embedding(read("speaker-a"))
        try require(reference.count == model.dimensions && reference.allSatisfy { $0.isFinite }, "Invalid embedding")
        try require(abs(SpeakerModel.similarity(reference, reference) - 1) < 0.0001, "Embedding is not normalized")
        var sameScores: [Float] = []
        var otherScores: [Float] = []
        var cleanScores: [Float] = []
        let started = Date()
        var denoisedDuration: Double = 0
        var denoisingSeconds: Double = 0
        for name in ["speaker-a-test", "speaker-a-test-2", "speaker-b-test", "speaker-b-test-2", "speaker-c-test"] {
            let samples = try read(name)
            let score = try SpeakerModel.similarity(reference, model.embedding(samples))
            let start = Date()
            let cleaned = clean(samples, model: model)
            denoisingSeconds += Date().timeIntervalSince(start)
            denoisedDuration += Double(samples.count) / 16000
            try require(!cleaned.isEmpty && cleaned.allSatisfy { $0.isFinite }, "Non-finite or empty denoiser output")
            try require(abs(cleaned.count - samples.count) <= 512, "Denoiser dropped too many samples")
            let cleanScore = try SpeakerModel.similarity(reference, model.embedding(cleaned))
            print("\(name): raw=\(score), denoised=\(cleanScore), samples=\(samples.count) → \(cleaned.count)")
            if name.hasPrefix("speaker-a") { sameScores.append(score); cleanScores.append(cleanScore) }
            else { otherScores.append(max(score, cleanScore)) }
        }
        print("Model=\(filename), dimensions=\(model.dimensions)")
        try require(sameScores.min()! > otherScores.max()! + 0.15, "Same-speaker scores must exceed different-speaker scores by 0.15")
        try require((sameScores + cleanScores).allSatisfy { $0 > 0.55 } && otherScores.allSatisfy { $0 < 0.55 }, "Fixture identities must be separated at the app's initial threshold")
        // Deterministic stationary noise exercises the actual GTCRN weights.
        var seed: UInt32 = 12345
        let noise: [Float] = (0..<48000).map { _ in
            seed = 1664525 &* seed &+ 1013904223
            return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.12
        }
        let noiseOutput = clean(noise, model: model)
        let noiseRatio = rms(noiseOutput) / rms(noise)
        print("Stationary-noise RMS ratio=\(noiseRatio)")
        try require(!noiseOutput.isEmpty && noiseRatio.isFinite && noiseRatio < 0.75, "Stationary-noise fixture was not attenuated")
        try require(SpeakerModel.normalized([.nan]).isEmpty, "Non-finite embeddings should fail closed")
        do {
            _ = try model.embedding([Float](repeating: .nan, count: 32000))
            throw HearlyFailure.message("FAIL: Non-finite audio accepted")
        } catch let error as HearlyFailure {
            if error.localizedDescription.hasPrefix("FAIL:") { throw error }
        }
        print("PASS: 6 WAV decodes agree; 2 held-out same-speaker and 3 other-speaker recordings separated.")
        print("PASS: GTCRN processed \(denoisedDuration)s in \(denoisingSeconds)s; total regression \(Date().timeIntervalSince(started))s.")
        print("LIMIT: Chinese-language, three-speaker regression only; not a production false-accept/false-reject benchmark or an overlapping-speaker separation test.")
    }
}
