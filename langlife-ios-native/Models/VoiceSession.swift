import Foundation

struct VoiceTranscriptEntry: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Equatable {
        case agent
        case user
    }

    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}

struct SavedVocabWord: Encodable {
    let chinese: String
    let pinyin: String
    let english: String
    let example: String?
    let examplePinyin: String?
    let exampleEnglish: String?

    enum CodingKeys: String, CodingKey {
        case chinese, pinyin, english, example
        case examplePinyin = "examplePinyin"
        case exampleEnglish = "exampleEnglish"
    }
}

struct VoiceSessionCompleteRequest: Encodable {
    let startedAt: String
    let durationSeconds: Int
    let summary: String?
    let score: Int?
    let wordsPracticed: [SavedVocabWord]

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case durationSeconds = "duration_seconds"
        case summary, score
        case wordsPracticed = "words_practiced"
    }
}

struct VoiceSessionCompleteResponse: Decodable {
    let sessionId: String
    let newCards: [NewCard]

    struct NewCard: Decodable {
        let id: String
        let chinese: String
        let pinyin: String
        let english: String
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case newCards = "new_cards"
    }
}
