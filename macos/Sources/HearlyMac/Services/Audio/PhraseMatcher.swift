import Foundation

struct PhraseMatchProgress: Equatable, Sendable {
    let recognizedText: String
    let matchedWordCount: Int
    let totalWordCount: Int
    var fraction: Double { totalWordCount == 0 ? 0 : Double(matchedWordCount) / Double(totalWordCount) }
    var isComplete: Bool { totalWordCount > 0 && matchedWordCount == totalWordCount }
}

/// Every prompt word must occur in order. Normalize punctuation, contractions,
/// and narrowly scoped Hearly ASR spellings, not arbitrary substitutions.
enum PhraseMatcher {
    static func match(expected: String, recognized: String) -> PhraseMatchProgress {
        let target = words(expected)
        let heard = words(recognized)
        guard !target.isEmpty, !heard.isEmpty else {
            return PhraseMatchProgress(recognizedText: recognized, matchedWordCount: 0, totalWordCount: target.count)
        }
        var best = 0
        for start in heard.indices where heard[start] == target[0] {
            var count = 0
            for word in heard[start...] {
                if count < target.count, word == target[count] {
                    count += 1
                } else if word == "um" || word == "uh" || (count > 0 && word == target[count - 1]) {
                    continue
                } else { break }
                best = max(best, count)
                if count == target.count { break }
            }
        }
        return PhraseMatchProgress(recognizedText: recognized, matchedWordCount: best, totalWordCount: target.count)
    }

    private static func words(_ value: String) -> [String] {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en-US"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "i'm", with: "i am")
            .replacingOccurrences(of: "it's", with: "it is")
            .replacingOccurrences(of: "that's", with: "that is")
        let raw = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var result: [String] = []
        var index = 0
        while index < raw.count {
            if index + 1 < raw.count, raw[index] == "hear", ["lee", "ly"].contains(raw[index + 1]) {
                result.append("hearly")
                index += 2
            } else {
                result.append(["hearly", "early", "nearly"].contains(raw[index]) ? "hearly" : raw[index])
                index += 1
            }
        }
        return result
    }
}
