import Foundation

struct SpeakSceneDetailCache: Codable {
    let outline: SpeakChatOutline
    let turns: [SpeakTurn]
    let cachedAt: Date
}

private struct SpeakSceneDetailIndexEntry: Codable {
    let sceneId: UUID
    let lastAccessedAt: Date
}

enum LocalSpeakSceneDetailStore {
    private static let storageKey = "speak_scene_detail"
    private static let indexKey = "speak_scene_detail_index"
    private static let maxEntries = 50

    static func load(userId: UUID, sceneId: UUID) -> SpeakSceneDetailCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: userId, sceneId: sceneId)) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(SpeakSceneDetailCache.self, from: data)
            touchIndex(userId: userId, sceneId: sceneId)
            return cache
        } catch {
            return nil
        }
    }

    static func save(_ cache: SpeakSceneDetailCache, userId: UUID, sceneId: UUID) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            UserDefaults.standard.set(data, forKey: cacheKey(for: userId, sceneId: sceneId))
            touchIndex(userId: userId, sceneId: sceneId)
            enforceLimit(for: userId)
        } catch {
            return
        }
    }

    static func clear(userId: UUID, sceneId: UUID) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: userId, sceneId: sceneId))
        removeFromIndex(userId: userId, sceneId: sceneId)
    }

    static func clearAll(userId: UUID) {
        let entries = loadIndex(for: userId)
        for entry in entries {
            UserDefaults.standard.removeObject(forKey: cacheKey(for: userId, sceneId: entry.sceneId))
        }
        UserDefaults.standard.removeObject(forKey: indexKeyForUser(userId))
    }

    private static func touchIndex(userId: UUID, sceneId: UUID) {
        var entries = loadIndex(for: userId)
        let now = Date()
        if let index = entries.firstIndex(where: { $0.sceneId == sceneId }) {
            entries[index] = SpeakSceneDetailIndexEntry(sceneId: sceneId, lastAccessedAt: now)
        } else {
            entries.append(SpeakSceneDetailIndexEntry(sceneId: sceneId, lastAccessedAt: now))
        }
        saveIndex(entries, for: userId)
    }

    private static func removeFromIndex(userId: UUID, sceneId: UUID) {
        var entries = loadIndex(for: userId)
        entries.removeAll { $0.sceneId == sceneId }
        saveIndex(entries, for: userId)
    }

    private static func enforceLimit(for userId: UUID) {
        var entries = loadIndex(for: userId)
        guard entries.count > maxEntries else { return }
        entries.sort { $0.lastAccessedAt < $1.lastAccessedAt }
        let overflow = entries.count - maxEntries
        let toRemove = entries.prefix(overflow)
        for entry in toRemove {
            UserDefaults.standard.removeObject(forKey: cacheKey(for: userId, sceneId: entry.sceneId))
        }
        entries.removeFirst(overflow)
        saveIndex(entries, for: userId)
    }

    private static func loadIndex(for userId: UUID) -> [SpeakSceneDetailIndexEntry] {
        guard let data = UserDefaults.standard.data(forKey: indexKeyForUser(userId)) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SpeakSceneDetailIndexEntry].self, from: data)
        } catch {
            return []
        }
    }

    private static func saveIndex(_ entries: [SpeakSceneDetailIndexEntry], for userId: UUID) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            UserDefaults.standard.set(data, forKey: indexKeyForUser(userId))
        } catch {
            return
        }
    }

    private static func cacheKey(for userId: UUID, sceneId: UUID) -> String {
        "\(storageKey).\(userId.uuidString).\(sceneId.uuidString)"
    }

    private static func indexKeyForUser(_ userId: UUID) -> String {
        "\(indexKey).\(userId.uuidString)"
    }
}
