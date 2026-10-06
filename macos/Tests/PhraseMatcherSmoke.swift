import Foundation

@main
struct PhraseMatcherSmoke {
    static func main() {
        let phrase = "Hey Hearly, this is rehan. I am training my voice profile."
        let cases: [(String, String, Bool)] = [
            (phrase, phrase, true),
            (phrase, "HEY HEARLY THIS IS REHAN I AM TRAINING MY VOICE PROFILE", true),
            (phrase, "Hey early, this is rehan. I'm training my voice profile.", true),
            (phrase, "Hey hear lee this is rehan I am training my voice profile", true),
            (phrase, "Hey nearly this is rehan I am training my voice profile", true),
            (phrase, "Hey Hearly, this is rehan", false),
            (phrase, "Hey Hearly this is someone I am training my voice profile", false),
            (phrase, "Hey Hearly this is rehan I training my voice profile", false),
            (phrase, "Hey Hearly this is rehan I am voice training my profile", false),
            (phrase, "The weather is nice today and there is noise in this room", false),
            (phrase, "", false),
            ("", "anything", false),
            (phrase, "Hey Hearly uh this is rehan I am training my voice profile", true),
            (phrase, "Hey Hearly this is rehan I I am training my voice profile", true),
            (phrase, "Wrong start. " + phrase, true),
            (phrase, "Hey Hearly wrong start. " + phrase, true),
            ("Keep my voice clear.", "keep my voice clearly", false),
            ("This is my natural speaking voice.", "This is my natural speaking voice", true)
        ]
        for (index, test) in cases.enumerated() {
            let result = PhraseMatcher.match(expected: test.0, recognized: test.1)
            precondition(result.isComplete == test.2, "Case \(index + 1) failed: \(result)")
            precondition((0...1).contains(result.fraction), "Invalid progress")
        }
        let partial = PhraseMatcher.match(expected: phrase, recognized: "Hey Hearly this is")
        precondition(partial.matchedWordCount == 4 && !partial.isComplete)
        print("PASS: \(cases.count + 1) phrase matching checks; missing, reordered, unrelated and empty speech cannot complete enrollment.")
    }
}
