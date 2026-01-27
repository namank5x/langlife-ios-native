import Foundation
import GRDB

struct SpeakSceneSyncState: Codable {
    let lastSyncAt: Date
    let lastServerCreatedAt: Date?
}

enum LocalSpeakSceneStore {
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
        let userKey = LocalStoreKeys.userKey(userId)
        return AppDatabase.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, title, description, tags, level, created_at
                FROM speak_scenes
                WHERE user_id = ?
                ORDER BY created_at DESC
                """,
                arguments: [userKey]
            )
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                let tagsJson: String = row["tags"]
                let tags = LocalStoreCoders.decode([String].self, from: tagsJson) ?? []
                let levelRaw: String = row["level"]
                guard let level = SpeakScene.Level(rawValue: levelRaw) else { return nil }
                let createdAtSeconds: Double? = row["created_at"]
                return SpeakScene(
                    id: id,
                    title: row["title"],
                    description: row["description"],
                    tags: tags,
                    level: level,
                    createdAt: createdAtSeconds.map { Date(timeIntervalSince1970: $0) }
                )
            }
        }
    }

    static func save(_ scenes: [SpeakScene], userId: UUID?) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM speak_scenes WHERE user_id = ?",
                arguments: [userKey]
            )
            for scene in scenes {
                guard let tagsJson = LocalStoreCoders.encode(scene.tags) else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO speak_scenes
                        (id, user_id, title, description, tags, level, created_at, updated_at)
                    VALUES
                        (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        scene.id.uuidString,
                        userKey,
                        scene.title,
                        scene.description,
                        tagsJson,
                        scene.level.rawValue,
                        scene.createdAt?.timeIntervalSince1970,
                        nil
                    ]
                )
            }
        }
    }

    static func clear(userId: UUID?) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM speak_scenes WHERE user_id = ?",
                arguments: [userKey]
            )
        }
        if let userId {
            clearSyncState(userId: userId)
        }
    }

    static func loadSyncState(userId: UUID) -> SpeakSceneSyncState? {
        guard let state = LocalSyncStateStore.load(entity: .speakScenes, userId: userId) else {
            return nil
        }
        return SpeakSceneSyncState(
            lastSyncAt: state.lastSyncAt,
            lastServerCreatedAt: state.lastServerCreatedAt
        )
    }

    static func saveSyncState(_ state: SpeakSceneSyncState, userId: UUID) {
        LocalSyncStateStore.save(
            entity: .speakScenes,
            userId: userId,
            state: .init(lastSyncAt: state.lastSyncAt, lastServerCreatedAt: state.lastServerCreatedAt)
        )
    }

    static func clearSyncState(userId: UUID) {
        LocalSyncStateStore.clear(entity: .speakScenes, userId: userId)
    }
}
