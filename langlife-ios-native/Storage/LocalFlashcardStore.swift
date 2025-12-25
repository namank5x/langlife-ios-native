import Foundation

struct FlashcardSyncState: Codable {
    let lastSyncAt: Date
    let lastServerCreatedAt: Date?
}

enum LocalFlashcardStore {
    private static let storageKey = "flashcards"
    private static let syncKey = "flashcards_sync"

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
        guard let data = UserDefaults.standard.data(forKey: cardsKey(for: userId)) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Flashcard].self, from: data)
        } catch {
            return nil
        }
    }

    static func save(_ cards: [Flashcard], userId: UUID?) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cards)
            UserDefaults.standard.set(data, forKey: cardsKey(for: userId))
        } catch {
            return
        }
    }

    static func clear(userId: UUID?) {
        UserDefaults.standard.removeObject(forKey: cardsKey(for: userId))
        if let userId {
            clearSyncState(userId: userId)
        }
    }

    static func loadSyncState(userId: UUID) -> FlashcardSyncState? {
        guard let data = UserDefaults.standard.data(forKey: syncKeyForUser(userId)) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(FlashcardSyncState.self, from: data)
        } catch {
            return nil
        }
    }

    static func saveSyncState(_ state: FlashcardSyncState, userId: UUID) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: syncKeyForUser(userId))
        } catch {
            return
        }
    }

    static func clearSyncState(userId: UUID) {
        UserDefaults.standard.removeObject(forKey: syncKeyForUser(userId))
    }

    private static func cardsKey(for userId: UUID?) -> String {
        guard let userId else { return storageKey }
        return "\(storageKey).\(userId.uuidString)"
    }

    private static func syncKeyForUser(_ userId: UUID) -> String {
        "\(syncKey).\(userId.uuidString)"
    }
}
