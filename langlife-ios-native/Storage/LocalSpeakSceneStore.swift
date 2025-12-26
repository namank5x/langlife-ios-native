import Foundation

struct SpeakSceneSyncState: Codable {
    let lastSyncAt: Date
    let lastServerCreatedAt: Date?
}

enum LocalSpeakSceneStore {
    private static let storageKey = "speak_scenes"
    private static let syncKey = "speak_scenes_sync"

    static func load() -> [SpeakScene]? {
        load(userId: nil)
    }

    static func save(_ scenes: [SpeakScene]) {
        save(scenes, userId: nil)
    }

    static func clear() {
        clear(userId: nil)
    }

    static func load(userId: UUID?) -> [SpeakScene]? {
        guard let data = UserDefaults.standard.data(forKey: scenesKey(for: userId)) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SpeakScene].self, from: data)
        } catch {
            return nil
        }
    }

    static func save(_ scenes: [SpeakScene], userId: UUID?) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(scenes)
            UserDefaults.standard.set(data, forKey: scenesKey(for: userId))
        } catch {
            return
        }
    }

    static func clear(userId: UUID?) {
        UserDefaults.standard.removeObject(forKey: scenesKey(for: userId))
        if let userId {
            clearSyncState(userId: userId)
        }
    }

    static func loadSyncState(userId: UUID) -> SpeakSceneSyncState? {
        guard let data = UserDefaults.standard.data(forKey: syncKeyForUser(userId)) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SpeakSceneSyncState.self, from: data)
        } catch {
            return nil
        }
    }

    static func saveSyncState(_ state: SpeakSceneSyncState, userId: UUID) {
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

    private static func scenesKey(for userId: UUID?) -> String {
        guard let userId else { return storageKey }
        return "\(storageKey).\(userId.uuidString)"
    }

    private static func syncKeyForUser(_ userId: UUID) -> String {
        "\(syncKey).\(userId.uuidString)"
    }
}
