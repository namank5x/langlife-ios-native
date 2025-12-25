import Foundation

enum Rating: Int {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

enum FSRSConfig {
    static let requestRetention = 0.9
    static let defaultDifficulty = 0.3
    static let defaultStability = 0.5
    static let newCardsPerSession = 20
    static let maxLearningCards = 10
    static let graduationThreshold = 2
    static let learningSteps = [3, 5, 8]
}

enum FSRS {
    private static let decay = -0.5
    private static let factor = 19.0 / 81.0

    static func getRetrievability(for card: Flashcard) -> Double {
        if card.state == .new { return 0 }
        if card.stability <= 0 { return 0 }
        guard let elapsedDays = elapsedDays(since: card.lastReviewAt) else { return 0 }

        let retrievability = pow(1 + (factor * elapsedDays) / card.stability, decay)
        return clamp(retrievability, min: 0, max: 1)
    }

    static func isDue(_ card: Flashcard) -> Bool {
        if card.state == .new { return false }
        if card.state == .learning || card.state == .relearning { return true }
        return getRetrievability(for: card) < FSRSConfig.requestRetention
    }

    static func reviewCard(_ card: Flashcard, rating: Rating) -> Flashcard {
        let now = Date()
        let isLearning = card.state == .new || card.state == .learning || card.state == .relearning
        let retrievability = isLearning ? 0 : getRetrievability(for: card)

        var newState = card.state
        var newLearningStep = card.learningStep
        var newLapses = card.lapses

        if rating == .again {
            if card.state == .new || card.state == .review {
                newState = card.state == .new ? .learning : .relearning
                newLapses = card.lapses + 1
            }
            newLearningStep = 0
        } else if isLearning {
            newLearningStep = card.learningStep + 1
            if rating == .easy || newLearningStep >= FSRSConfig.graduationThreshold {
                newState = .review
                newLearningStep = 0
            }
        }

        let newDifficulty: Double
        if card.state == .new {
            newDifficulty = getDifficultyFromRating(rating)
        } else {
            newDifficulty = getNextDifficulty(difficulty: card.difficulty, rating: rating)
        }

        let newStability = getNextStability(
            stability: card.stability,
            difficulty: newDifficulty,
            retrievability: retrievability,
            rating: rating,
            isLearning: isLearning
        )

        return Flashcard(
            id: card.id,
            chinese: card.chinese,
            pinyin: card.pinyin,
            english: card.english,
            example: card.example,
            examplePinyin: card.examplePinyin,
            exampleEnglish: card.exampleEnglish,
            createdAt: card.createdAt,
            state: newState,
            stability: newStability,
            difficulty: newDifficulty,
            lastReviewAt: now,
            lapses: newLapses,
            reps: card.reps + 1,
            learningStep: newLearningStep
        )
    }

    private static func getNextDifficulty(difficulty: Double, rating: Rating) -> Double {
        let adjustments: [Rating: Double] = [
            .again: 0.1,
            .hard: 0.05,
            .good: -0.02,
            .easy: -0.1,
        ]
        let newDifficulty = difficulty + (adjustments[rating] ?? 0)
        return clamp(newDifficulty, min: 0, max: 1)
    }

    private static func getNextStability(
        stability: Double,
        difficulty: Double,
        retrievability: Double,
        rating: Rating,
        isLearning: Bool
    ) -> Double {
        if isLearning {
            let initialStabilities: [Rating: Double] = [
                .again: 0.25,
                .hard: 0.5,
                .good: 1,
                .easy: 3,
            ]
            return initialStabilities[rating] ?? FSRSConfig.defaultStability
        }

        if rating == .again {
            return max(0.1, stability * 0.2)
        }

        let baseMultipliers: [Rating: Double] = [
            .again: 0.2,
            .hard: 1.2,
            .good: 2.5,
            .easy: 4.0,
        ]
        let difficultyModifier = 1 - difficulty * 0.5
        let retrievabilityBonus = 1 + (1 - retrievability) * 0.5
        let multiplier = (baseMultipliers[rating] ?? 1) * difficultyModifier * retrievabilityBonus
        return stability * multiplier
    }

    private static func getDifficultyFromRating(_ rating: Rating) -> Double {
        let difficulties: [Rating: Double] = [
            .again: 0.7,
            .hard: 0.5,
            .good: 0.3,
            .easy: 0.1,
        ]
        return difficulties[rating] ?? FSRSConfig.defaultDifficulty
    }

    private static func elapsedDays(since date: Date?) -> Double? {
        guard let date else { return nil }
        return Date().timeIntervalSince(date) / (24 * 60 * 60)
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
