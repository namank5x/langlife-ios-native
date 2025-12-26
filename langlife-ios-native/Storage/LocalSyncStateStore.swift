import Foundation
import GRDB

enum LocalSyncStateStore {
    enum Entity: String {
        case speakScenes = "speak_scenes"
        case flashcards = "flashcards"
    }

    struct State {
        let lastSyncAt: Date
        let lastServerCreatedAt: Date?
    }

    static func load(entity: Entity, userId: UUID) -> State? {
        let userKey = LocalStoreKeys.userKey(userId)
        return AppDatabase.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT last_sync_at, last_server_created_at FROM sync_state WHERE entity = ? AND user_id = ?",
                arguments: [entity.rawValue, userKey]
            )
            guard let row else { return nil }
            let lastSyncAtSeconds: Double = row["last_sync_at"]
            let lastServerSeconds: Double? = row["last_server_created_at"]
            return State(
                lastSyncAt: Date(timeIntervalSince1970: lastSyncAtSeconds),
                lastServerCreatedAt: lastServerSeconds.map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    static func save(entity: Entity, userId: UUID, state: State) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: """
                INSERT INTO sync_state (entity, user_id, last_sync_at, last_server_created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(entity, user_id) DO UPDATE SET
                    last_sync_at = excluded.last_sync_at,
                    last_server_created_at = excluded.last_server_created_at
                """,
                arguments: [
                    entity.rawValue,
                    userKey,
                    state.lastSyncAt.timeIntervalSince1970,
                    state.lastServerCreatedAt?.timeIntervalSince1970
                ]
            )
        }
    }

    static func clear(entity: Entity, userId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM sync_state WHERE entity = ? AND user_id = ?",
                arguments: [entity.rawValue, userKey]
            )
        }
    }
}
