import Foundation
import Supabase

struct FlashcardRepository {
    func fetchCards(for userId: UUID) async throws -> [Flashcard] {
        try await supabase
            .from("flashcards")
            .select(
                "id, chinese, pinyin, english, example, example_pinyin, example_english, state, stability, difficulty, last_review_at, lapses, reps, learning_step"
            )
            .eq("user_id", value: userId.uuidString)
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

    func update(card: Flashcard, userId: UUID) async throws {
        let payload = FlashcardReviewUpdate(card: card)
        _ = try await supabase
            .from("flashcards")
            .update(payload)
            .eq("id", value: card.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
