import Foundation

enum LocalFlashcardStore {
    private static let storageKey = "flashcards"

    static func load() -> [Flashcard]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
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

    static func save(_ cards: [Flashcard]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cards)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            return
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
