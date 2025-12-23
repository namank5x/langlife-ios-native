import Foundation

enum SpeakRole: String, Codable, Hashable {
    case ai
    case user
}

struct SpeakGlossToken: Codable, Hashable {
    let chinese: String?
    let pinyin: String
    let english: String
    let isPunctuation: Bool?
}

struct SpeakLine: Codable, Hashable {
    let chinese: String
    let pinyin: String
    let english: String
    let gloss: [SpeakGlossToken]
    let cue: String?
}

struct SpeakTurn: Identifiable, Codable, Hashable {
    let step: Int
    let aiLine: SpeakLine
    let userLine: SpeakLine
    let speakFirst: SpeakRole
    let focusHint: String?

    var id: Int { step }
}

struct SpeakTurnOutline: Identifiable, Codable, Hashable {
    let step: Int
    let speakFirst: SpeakRole
    let aiIntent: String
    let userIntent: String
    let focusHint: String?

    var id: Int { step }
}

struct SpeakChatOutline: Codable, Hashable {
    let sceneId: UUID
    let turns: [SpeakTurnOutline]
    let practiceTip: String?
}
