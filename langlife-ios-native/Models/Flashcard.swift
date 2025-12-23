import Foundation

enum CardState: String, Codable {
    case new
    case learning
    case review
    case relearning
}

struct Flashcard: Identifiable, Codable, Hashable {
    let id: UUID
    var chinese: String
    var pinyin: String
    var english: String
    var example: String?
    var examplePinyin: String?
    var exampleEnglish: String?

    var state: CardState
    var stability: Double
    var difficulty: Double
    var lastReviewAt: Date?
    var lapses: Int
    var reps: Int
    var learningStep: Int

    enum CodingKeys: String, CodingKey {
        case id
        case chinese
        case pinyin
        case english
        case example
        case examplePinyin = "example_pinyin"
        case exampleEnglish = "example_english"
        case state
        case stability
        case difficulty
        case lastReviewAt = "last_review_at"
        case lapses
        case reps
        case learningStep = "learning_step"
    }
}

struct FlashcardInsert: Encodable {
    let id: UUID
    let userId: UUID
    let chinese: String
    let pinyin: String
    let english: String
    let example: String?
    let examplePinyin: String?
    let exampleEnglish: String?
    let phraseKey: String?
    let state: CardState
    let stability: Double
    let difficulty: Double
    let lastReviewAt: Date?
    let lapses: Int
    let reps: Int
    let learningStep: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case chinese
        case pinyin
        case english
        case example
        case examplePinyin = "example_pinyin"
        case exampleEnglish = "example_english"
        case phraseKey = "phrase_key"
        case state
        case stability
        case difficulty
        case lastReviewAt = "last_review_at"
        case lapses
        case reps
        case learningStep = "learning_step"
    }
}

struct FlashcardReviewUpdate: Encodable {
    let state: CardState
    let stability: Double
    let difficulty: Double
    let lastReviewAt: Date?
    let lapses: Int
    let reps: Int
    let learningStep: Int

    init(card: Flashcard) {
        state = card.state
        stability = card.stability
        difficulty = card.difficulty
        lastReviewAt = card.lastReviewAt
        lapses = card.lapses
        reps = card.reps
        learningStep = card.learningStep
    }

    enum CodingKeys: String, CodingKey {
        case state
        case stability
        case difficulty
        case lastReviewAt = "last_review_at"
        case lapses
        case reps
        case learningStep = "learning_step"
    }
}

extension Flashcard {
    static func initial(from seed: FlashcardSeed) -> Flashcard {
        Flashcard(
            id: UUID(),
            chinese: seed.chinese,
            pinyin: seed.pinyin,
            english: seed.english,
            example: seed.example,
            examplePinyin: seed.examplePinyin,
            exampleEnglish: seed.exampleEnglish,
            state: .new,
            stability: 0,
            difficulty: 0.3,
            lastReviewAt: nil,
            lapses: 0,
            reps: 0,
            learningStep: 0
        )
    }

    func toInsert(userId: UUID) -> FlashcardInsert {
        FlashcardInsert(
            id: id,
            userId: userId,
            chinese: chinese,
            pinyin: pinyin,
            english: english,
            example: example,
            examplePinyin: examplePinyin,
            exampleEnglish: exampleEnglish,
            phraseKey: FlashcardSeed.buildPhraseKey(chinese: chinese, pinyin: pinyin, english: english),
            state: state,
            stability: stability,
            difficulty: difficulty,
            lastReviewAt: lastReviewAt,
            lapses: lapses,
            reps: reps,
            learningStep: learningStep
        )
    }
}
