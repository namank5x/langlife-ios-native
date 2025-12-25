import Combine
import Foundation

@MainActor
final class FlashcardStore: ObservableObject {
    @Published private(set) var cards: [Flashcard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository = FlashcardRepository()
    private var lastLoadedUserId: UUID?

    func loadIfNeeded(for userId: UUID?) async {
        guard !isLoading else { return }
        if lastLoadedUserId == userId, !cards.isEmpty { return }
        await load(for: userId)
    }

    func refresh(for userId: UUID?) async {
        guard !isLoading else { return }
        await load(for: userId, force: true)
    }

    func addCard(
        chinese: String,
        pinyin: String,
        english: String,
        userId: UUID
    ) async throws -> Flashcard {
        let newCard = Flashcard.newCard(
            chinese: chinese,
            pinyin: pinyin,
            english: english
        )
        let previousCards = cards
        cards = cards + [newCard]

        do {
            try await repository.insert(cards: [newCard], userId: userId)
        } catch {
            cards = previousCards
            throw error
        }

        return newCard
    }

    func updateContent(
        cardId: UUID,
        chinese: String,
        pinyin: String,
        english: String,
        userId: UUID
    ) async throws -> Flashcard {
        guard let index = cards.firstIndex(where: { $0.id == cardId }) else {
            throw FlashcardStoreError.cardNotFound
        }

        let previousCard = cards[index]
        let updatedCard = Flashcard(
            id: previousCard.id,
            chinese: chinese,
            pinyin: pinyin,
            english: english,
            example: previousCard.example,
            examplePinyin: previousCard.examplePinyin,
            exampleEnglish: previousCard.exampleEnglish,
            state: previousCard.state,
            stability: previousCard.stability,
            difficulty: previousCard.difficulty,
            lastReviewAt: previousCard.lastReviewAt,
            lapses: previousCard.lapses,
            reps: previousCard.reps,
            learningStep: previousCard.learningStep
        )

        cards[index] = updatedCard

        do {
            try await repository.updateContent(
                cardId: cardId,
                userId: userId,
                chinese: chinese,
                pinyin: pinyin,
                english: english
            )
        } catch {
            cards[index] = previousCard
            throw error
        }

        return updatedCard
    }

    func deleteCard(cardId: UUID, userId: UUID) async throws {
        guard let index = cards.firstIndex(where: { $0.id == cardId }) else {
            throw FlashcardStoreError.cardNotFound
        }

        let previousCards = cards
        cards.remove(at: index)

        do {
            try await repository.delete(cardId: cardId, userId: userId)
        } catch {
            cards = previousCards
            throw error
        }
    }

    func updateCard(_ updatedCard: Flashcard) {
        cards = cards.map { $0.id == updatedCard.id ? updatedCard : $0 }
    }

    func persistReview(_ updatedCard: Flashcard, userId: UUID?) async throws {
        if let userId {
            try await repository.update(card: updatedCard, userId: userId)
            return
        }

        LocalFlashcardStore.save(cards)
    }

    private func load(for userId: UUID?, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, lastLoadedUserId == userId, !cards.isEmpty { return }

        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        lastLoadedUserId = userId

        if let userId {
            do {
                let fetchedCards = try await repository.fetchCards(for: userId)
                if fetchedCards.isEmpty {
                    let seeded = FlashcardSeed.defaults.map(Flashcard.initial(from:))
                    try await repository.insert(cards: seeded, userId: userId)
                    LocalFlashcardStore.clear()
                    cards = seeded
                } else {
                    cards = fetchedCards
                }
            } catch {
                errorMessage = "Could not load cards. Showing local data instead."
                loadFromLocalFallback()
            }
            return
        }

        loadFromLocalFallback()
    }

    private func loadFromLocalFallback() {
        if let local = LocalFlashcardStore.load(), !local.isEmpty {
            cards = local
            return
        }

        let seeded = FlashcardSeed.defaults.map(Flashcard.initial(from:))
        LocalFlashcardStore.save(seeded)
        cards = seeded
    }
}

enum FlashcardStoreError: Error {
    case cardNotFound
}
