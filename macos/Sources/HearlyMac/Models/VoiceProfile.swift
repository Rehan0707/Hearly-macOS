import Foundation

struct VoiceProfile: Codable {
    var name: String
    var embedding: [Float]
    var model: String
    var createdAt = Date()
}

struct TranscriptRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
}
