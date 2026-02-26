import Foundation
import Supabase

struct FlashcardRepository {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func fetchCards(for userId: UUID) async throws -> [Flashcard] {
        try await supabase
            .from("flashcards")
            .select(
                "id, chinese, pinyin, english, example, example_pinyin, example_english, created_at, state, stability, difficulty, last_review_at, lapses, reps, learning_step"
            )
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchCardsCreated(after createdAt: Date, userId: UUID) async throws -> [Flashcard] {
        let cutoff = Self.iso8601Formatter.string(from: createdAt)
        return try await supabase
            .from("flashcards")
            .select(
                "id, chinese, pinyin, english, example, example_pinyin, example_english, created_at, state, stability, difficulty, last_review_at, lapses, reps, learning_step"
            )
            .eq("user_id", value: userId.uuidString)
            .gt("created_at", value: cutoff)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func insert(cards: [Flashcard], userId: UUID) async throws {
        let payload = cards.map { $0.toInsert(userId: userId) }
        _ = try await supabase
            .from("flashcards")
            .insert(payload)
            .execute()
    }

    func insertBatched(cards: [Flashcard], userId: UUID, batchSize: Int = 100) async throws {
        for batch in cards.chunked(into: batchSize) {
            try await insert(cards: batch, userId: userId)
        }
    }

    func upsertIgnoringDuplicates(cards: [Flashcard], userId: UUID) async throws {
        let payload = cards.map { $0.toInsert(userId: userId) }
        _ = try await supabase
            .from("flashcards")
            .upsert(payload, onConflict: "user_id,phrase_key", ignoreDuplicates: true)
            .execute()
    }

    func update(card: Flashcard, userId: UUID) async throws {
        let payload = FlashcardReviewUpdate(card: card)
        _ = try await supabase
            .from("flashcards")
            .update(payload)
            .eq("id", value: card.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func updateContent(
        cardId: UUID,
        userId: UUID,
        chinese: String,
        pinyin: String,
        english: String
    ) async throws {
        let payload = FlashcardContentUpdate(
            chinese: chinese,
            pinyin: pinyin,
            english: english,
            phraseKey: FlashcardSeed.buildPhraseKey(
                chinese: chinese,
                pinyin: pinyin,
                english: english
            )
        )
        _ = try await supabase
            .from("flashcards")
            .update(payload)
            .eq("id", value: cardId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func delete(cardId: UUID, userId: UUID) async throws {
        _ = try await supabase
            .from("flashcards")
            .delete()
            .eq("id", value: cardId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
