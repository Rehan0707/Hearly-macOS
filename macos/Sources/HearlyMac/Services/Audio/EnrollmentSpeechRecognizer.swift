import Foundation

/// Receives the same 16 kHz mono samples used to construct the voiceprint.
/// Never opens a second microphone or sends recordings to a server.
@MainActor
final class EnrollmentSpeechRecognizer {
    var onProgress: ((PhraseMatchProgress) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private let speech = TranscriptService()
    private var expectedPhrase = ""
    private var generation = UUID()
    private var completionTask: Task<Void, Never>?
    private var latestMatch: PhraseMatchProgress?

    init() {
        speech.onText = { [weak self] text in self?.receive(text) }
        speech.onError = { [weak self] message in
            guard let self else { return }
            self.stop()
            self.onError?(message)
        }
        speech.onStatus = { [weak self] message in self?.onStatus?(message) }
    }

    func start(expectedPhrase: String) async throws {
        stop()
        let token = generation
        self.expectedPhrase = expectedPhrase
        guard PhraseMatcher.match(expected: expectedPhrase, recognized: "").totalWordCount > 0 else {
            throw HearlyFailure.message("The voice-training phrase is empty. Restart voice training.")
        }
        try await speech.start()
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
    }

    func append(_ samples: [Float]) { speech.append(samples) }

    func stop() {
        generation = UUID()
        completionTask?.cancel()
        completionTask = nil
        latestMatch = nil
        expectedPhrase = ""
        speech.stop()
    }

    private func receive(_ text: String) {
        guard !expectedPhrase.isEmpty else { return }
        let progress = PhraseMatcher.match(expected: expectedPhrase, recognized: text)
        latestMatch = progress
        guard progress.isComplete else {
            completionTask?.cancel()
            completionTask = nil
            onProgress?(progress)
            return
        }
        // Partial recognition may be revised. Require the complete phrase to
        // remain stable briefly before permitting the voiceprint capture.
        guard completionTask == nil else { return }
        let token = generation
        completionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self, self.generation == token,
                  let stable = self.latestMatch, stable.isComplete else { return }
            self.onProgress?(stable)
        }
    }
}
