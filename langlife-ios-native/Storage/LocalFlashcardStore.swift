import Foundation
import GRDB

struct FlashcardSyncState: Codable {
    let lastSyncAt: Date
    let lastServerCreatedAt: Date?
}

enum LocalFlashcardStore {
    static func load() -> [Flashcard]? {
        load(userId: nil)
    }

    static func save(_ cards: [Flashcard]) {
        save(cards, userId: nil)
    }

    static func clear() {
        clear(userId: nil)
    }

    static func load(userId: UUID?) -> [Flashcard]? {
        let userKey = LocalStoreKeys.userKey(userId)
        return AppDatabase.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, chinese, pinyin, english, example, example_pinyin, example_english,
                       state, stability, difficulty, last_review_at, lapses, reps, learning_step, created_at
                FROM flashcards
                WHERE user_id = ?
                ORDER BY created_at DESC
                """,
                arguments: [userKey]
            )
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                let stateRaw: String = row["state"]
                guard let state = CardState(rawValue: stateRaw) else { return nil }
                let createdAtSeconds: Double? = row["created_at"]
                let lastReviewSeconds: Double? = row["last_review_at"]
                return Flashcard(
                    id: id,
                    chinese: row["chinese"],
                    pinyin: row["pinyin"],
                    english: row["english"],
                    example: row["example"],
                    examplePinyin: row["example_pinyin"],
                    exampleEnglish: row["example_english"],
                    createdAt: createdAtSeconds.map { Date(timeIntervalSince1970: $0) },
                    state: state,
                    stability: row["stability"],
                    difficulty: row["difficulty"],
                    lastReviewAt: lastReviewSeconds.map { Date(timeIntervalSince1970: $0) },
                    lapses: row["lapses"],
                    reps: row["reps"],
                    learningStep: row["learning_step"]
                )
            }
        }
    }

    static func save(_ cards: [Flashcard], userId: UUID?) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM flashcards WHERE user_id = ?",
                arguments: [userKey]
            )
            for card in cards {
                try db.execute(
                    sql: """
                    INSERT INTO flashcards
                        (id, user_id, chinese, pinyin, english, example, example_pinyin, example_english,
                         state, stability, difficulty, last_review_at, lapses, reps, learning_step, created_at, updated_at)
                    VALUES
                        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        card.id.uuidString,
                        userKey,
                        card.chinese,
                        card.pinyin,
                        card.english,
                        card.example,
                        card.examplePinyin,
                        card.exampleEnglish,
                        card.state.rawValue,
                        card.stability,
                        card.difficulty,
                        card.lastReviewAt?.timeIntervalSince1970,
                        card.lapses,
                        card.reps,
                        card.learningStep,
                        card.createdAt?.timeIntervalSince1970,
                        nil
                    ]
                )
            }
        }
    }

    static func clear(userId: UUID?) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM flashcards WHERE user_id = ?",
                arguments: [userKey]
            )
        }
        if let userId {
            clearSyncState(userId: userId)
        }
    }

    static func loadSyncState(userId: UUID) -> FlashcardSyncState? {
        guard let state = LocalSyncStateStore.load(entity: .flashcards, userId: userId) else {
            return nil
        }
        return FlashcardSyncState(
            lastSyncAt: state.lastSyncAt,
            lastServerCreatedAt: state.lastServerCreatedAt
        )
    }

    static func saveSyncState(_ state: FlashcardSyncState, userId: UUID) {
        LocalSyncStateStore.save(
            entity: .flashcards,
            userId: userId,
            state: .init(lastSyncAt: state.lastSyncAt, lastServerCreatedAt: state.lastServerCreatedAt)
        )
    }

    static func clearSyncState(userId: UUID) {
        LocalSyncStateStore.clear(entity: .flashcards, userId: userId)
    }
}
