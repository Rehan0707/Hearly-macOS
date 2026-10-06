import AVFoundation
import Foundation
import Speech

// Isolates the speech files from app/database startup and microphone access.
enum HearlyFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { value } else { nil } }
}

@main
struct OnDeviceSpeechSmoke {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count < 3 {
            if #available(macOS 26, *) {
                print("SpeechTranscriber available: \(SpeechTranscriber.isAvailable)")
                let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
                print("Supported English locale: \(locale?.identifier ?? "none")")
                if let locale {
                    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                    print("Model assets: \(await AssetInventory.status(forModules: [transcriber]))")
                }
            } else { print("This Mac requires the on-device SFSpeech compatibility path.") }
            print("PASS: speech files compiled; no microphone, user database or cloud service used.")
            return
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let expected = CommandLine.arguments[2]
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: input)
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 16_000 / file.processingFormat.sampleRate) + 64)!
        let converter = AVAudioConverter(from: file.processingFormat, to: target)!
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        var samples = Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
        samples += Array(repeating: 0, count: 16_000 * 3)
        let recognizer = EnrollmentSpeechRecognizer()
        var complete = false
        var failure: String?
        var lastText = ""
        recognizer.onStatus = { print("STATUS: \($0)") }
        recognizer.onProgress = {
            lastText = $0.recognizedText
            print("WORDS \($0.matchedWordCount)/\($0.totalWordCount): \($0.recognizedText)")
            complete = $0.isComplete
        }
        recognizer.onError = { failure = $0 }
        try await recognizer.start(expectedPhrase: expected)
        for start in stride(from: 0, to: samples.count, by: 320) {
            recognizer.append(Array(samples[start..<min(start + 320, samples.count)]))
            try await Task.sleep(nanoseconds: 20_000_000)
            if complete || failure != nil { break }
        }
        for _ in 0..<30 where !complete && failure == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        recognizer.stop()
        if let failure { throw HearlyFailure.message(failure) }
        guard complete else { throw HearlyFailure.message("Phrase was not accepted. Last recognized text: \(lastText)") }
        print("PASS: local Apple speech recognized and validated the complete supplied phrase.")
    }
}
