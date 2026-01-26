import Combine
import Foundation

@MainActor
final class FlashcardStore: ObservableObject {
    @Published private(set) var cards: [Flashcard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository = FlashcardRepository()
    private var lastLoadedUserId: UUID?
    private var isRefreshing = false
    private let syncTTL: TimeInterval = 10 * 60
    static let offlineMessage = "Offline. Sync will resume later."

    var isOfflineNotice: Bool {
        errorMessage == Self.offlineMessage
    }

    func loadIfNeeded(for userId: UUID?) async {
        if isRefreshing, lastLoadedUserId == userId { return }
        if let userId {
            if lastLoadedUserId != userId || cards.isEmpty {
                cards = []
                loadCachedCards(for: userId)
                lastLoadedUserId = userId
            }
            await refreshIfStale(for: userId)
            return
        }

        loadGuestCards()
    }

    func refresh(for userId: UUID?) async {
        if isRefreshing, lastLoadedUserId == userId { return }
        guard let userId else {
            loadGuestCards()
            return
        }

        await refreshIfStale(for: userId, force: true)
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
            LocalFlashcardStore.save(cards, userId: userId)
            touchSyncState(userId: userId)
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
            createdAt: previousCard.createdAt,
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
            LocalFlashcardStore.save(cards, userId: userId)
            touchSyncState(userId: userId)
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
            LocalFlashcardStore.save(cards, userId: userId)
            touchSyncState(userId: userId)
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
            do {
                try await repository.update(card: updatedCard, userId: userId)
                LocalFlashcardStore.save(cards, userId: userId)
                touchSyncState(userId: userId)
            } catch {
                LocalFlashcardStore.save(cards, userId: userId)
                throw error
            }
            return
        }

        LocalFlashcardStore.save(cards, userId: nil)
    }

    private func refreshIfStale(for userId: UUID, force: Bool = false) async {
        let syncState = LocalFlashcardStore.loadSyncState(userId: userId)
        if !force, let syncState {
            let age = Date().timeIntervalSince(syncState.lastSyncAt)
            if age < syncTTL { return }
        }

        await refreshFromServer(for: userId, syncState: syncState)
    }

    private func refreshFromServer(for userId: UUID, syncState: FlashcardSyncState?) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = cards.isEmpty
        defer {
            isRefreshing = false
            isLoading = false
        }

        errorMessage = nil
        lastLoadedUserId = userId

        do {
            if let lastServerCreatedAt = syncState?.lastServerCreatedAt {
                let newCards = try await repository.fetchCardsCreated(
                    after: lastServerCreatedAt,
                    userId: userId
                )
                guard lastLoadedUserId == userId else { return }
                if !newCards.isEmpty {
                    mergeNewCards(newCards)
                    LocalFlashcardStore.save(cards, userId: userId)
                }
                let maxCreatedAt = [lastServerCreatedAt, newCards.compactMap(\.createdAt).max()]
                    .compactMap { $0 }
                    .max()
                updateSyncState(userId: userId, lastServerCreatedAt: maxCreatedAt)
                return
            }

            let fetchedCards = try await repository.fetchCards(for: userId)
            guard lastLoadedUserId == userId else { return }
            if fetchedCards.isEmpty {
                cards = []
            } else {
                cards = fetchedCards
            }
            LocalFlashcardStore.save(cards, userId: userId)
            let maxCreatedAt = cards.compactMap(\.createdAt).max()
            updateSyncState(userId: userId, lastServerCreatedAt: maxCreatedAt)
        } catch {
            errorMessage = error.isOffline
                ? Self.offlineMessage
                : "Could not load cards right now."
            if cards.isEmpty {
                loadCachedCards(for: userId)
            }
        }
    }

    private func loadCachedCards(for userId: UUID) {
        if let local = LocalFlashcardStore.load(userId: userId), !local.isEmpty {
            cards = local
        }
    }

    private func mergeNewCards(_ newCards: [Flashcard]) {
        guard !newCards.isEmpty else { return }
        var updatedCards = cards
        var indexById = Dictionary(uniqueKeysWithValues: updatedCards.enumerated().map { ($0.element.id, $0.offset) })
        for card in newCards {
            if let index = indexById[card.id] {
                updatedCards[index] = card
            } else {
                indexById[card.id] = updatedCards.count
                updatedCards.append(card)
            }
        }
        cards = updatedCards
    }

    private func updateSyncState(userId: UUID, lastServerCreatedAt: Date?) {
        let state = FlashcardSyncState(
            lastSyncAt: Date(),
            lastServerCreatedAt: lastServerCreatedAt
        )
        LocalFlashcardStore.saveSyncState(state, userId: userId)
    }

    private func touchSyncState(userId: UUID) {
        let lastServerCreatedAt = LocalFlashcardStore.loadSyncState(userId: userId)?.lastServerCreatedAt
        updateSyncState(userId: userId, lastServerCreatedAt: lastServerCreatedAt)
    }

    private func clearUserCacheIfNeeded() {
        guard let loadedUserId = lastLoadedUserId else { return }
        LocalFlashcardStore.clear(userId: loadedUserId)
        lastLoadedUserId = nil
        cards = []
    }

    private func loadGuestCards() {
        errorMessage = nil
        clearUserCacheIfNeeded()
        if let cached = LocalFlashcardStore.load(userId: nil), !cached.isEmpty {
            cards = cached
            lastLoadedUserId = nil
            return
        }
        let seeds = Array(FlashcardSeed.defaults.prefix(15)).map(Flashcard.initial)
        cards = seeds
        LocalFlashcardStore.save(seeds, userId: nil)
        lastLoadedUserId = nil
    }
}

enum FlashcardStoreError: Error {
    case cardNotFound
}
