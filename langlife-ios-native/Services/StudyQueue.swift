import Foundation

enum CardCategory: String {
    case learning
    case due
    case new
    case extra
}

struct QueuedCard: Hashable {
    let card: Flashcard
    let priority: Int
    let category: CardCategory
}

enum StudyQueue {
    static func buildQueue(
        _ cards: [Flashcard],
        newCardLimit: Int = FSRSConfig.newCardsPerSession
    ) -> [QueuedCard] {
        var queue: [QueuedCard] = []
        var newCardCount = 0
        var learningCount = 0

        let sortedCards = cards.sorted { a, b in
            let aLearning = a.state == .learning || a.state == .relearning
            let bLearning = b.state == .learning || b.state == .relearning
            if aLearning != bLearning { return aLearning }

            if a.state == .review && b.state == .review {
                return FSRS.getRetrievability(for: a) < FSRS.getRetrievability(for: b)
            }

            return false
        }

        for card in sortedCards {
            if card.state == .learning || card.state == .relearning {
                if learningCount < FSRSConfig.maxLearningCards {
                    queue.append(QueuedCard(card: card, priority: 1, category: .learning))
                    learningCount += 1
                }
                continue
            }

            if card.state == .review && FSRS.isDue(card) {
                queue.append(QueuedCard(card: card, priority: 2, category: .due))
                continue
            }

            if card.state == .new {
                if newCardCount < newCardLimit {
                    queue.append(QueuedCard(card: card, priority: 3, category: .new))
                    newCardCount += 1
                }
                continue
            }

            if card.state == .review {
                let retrievability = FSRS.getRetrievability(for: card)
                if retrievability < 0.98 {
                    queue.append(QueuedCard(card: card, priority: 4, category: .extra))
                }
            }
        }

        return queue.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return FSRS.getRetrievability(for: a.card) < FSRS.getRetrievability(for: b.card)
        }
    }

    static func removeCard(_ queue: [QueuedCard], cardId: UUID) -> [QueuedCard] {
        queue.filter { $0.card.id != cardId }
    }

    static func reinsertCard(
        _ queue: [QueuedCard],
        card: Flashcard,
        positionsAhead: Int
    ) -> [QueuedCard] {
        let filtered = queue.filter { $0.card.id != card.id }
        let insertIndex = min(positionsAhead, filtered.count)
        let queuedCard = QueuedCard(card: card, priority: 1, category: .learning)

        var newQueue = filtered
        newQueue.insert(queuedCard, at: insertIndex)
        return newQueue
    }

    static func getReinsertPosition(consecutiveFailures: Int) -> Int {
        if consecutiveFailures >= 2 { return 1 }
        return FSRSConfig.learningSteps.first ?? 3
    }

    static func addExtraReviews(
        _ queue: [QueuedCard],
        cards: [Flashcard],
        count: Int = 10
    ) -> [QueuedCard] {
        let queuedIds = Set(queue.map { $0.card.id })

        let extraCards = cards
            .filter { $0.state == .review && !queuedIds.contains($0.id) }
            .map { (card: $0, retrievability: FSRS.getRetrievability(for: $0)) }
            .sorted { $0.retrievability < $1.retrievability }
            .prefix(count)
            .map { QueuedCard(card: $0.card, priority: 4, category: .extra) }

        return queue + extraCards
    }
}
