import Foundation
import GRDB

enum SceneOutboxStatus: String, Codable {
    case pending
    case failed
}

struct SceneOutboxItem: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var scene: SpeakScene
    var outline: SpeakChatOutline?
    var turns: [SpeakTurn]
    var status: SceneOutboxStatus
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastError: String?
    var updatedAt: Date
}

enum LocalSceneOutboxStore {
    static func load(userId: UUID) -> [SceneOutboxItem] {
        let userKey = LocalStoreKeys.userKey(userId)
        return AppDatabase.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT scene_id, scene_json, outline_json, turns_json, status,
                       attempt_count, last_attempt_at, last_error, updated_at
                FROM scene_outbox
                WHERE user_id = ?
                ORDER BY updated_at DESC
                """,
                arguments: [userKey]
            )
            return rows.compactMap { row in
                guard let sceneId = UUID(uuidString: row["scene_id"]) else { return nil }
                let sceneJson: String = row["scene_json"]
                guard let scene = LocalStoreCoders.decode(SpeakScene.self, from: sceneJson) else {
                    return nil
                }
                let outlineJson: String? = row["outline_json"]
                let turnsJson: String = row["turns_json"]
                let outline = LocalStoreCoders.decode(SpeakChatOutline.self, from: outlineJson)
                let turns = LocalStoreCoders.decode([SpeakTurn].self, from: turnsJson) ?? []
                let statusRaw: String = row["status"]
                let status = SceneOutboxStatus(rawValue: statusRaw) ?? .pending
                let attemptCount: Int = row["attempt_count"]
                let lastAttemptSeconds: Double? = row["last_attempt_at"]
                let updatedSeconds: Double = row["updated_at"]
                let lastError: String? = row["last_error"]
                return SceneOutboxItem(
                    id: sceneId,
                    userId: userId,
                    scene: scene,
                    outline: outline,
                    turns: turns,
                    status: status,
                    attemptCount: attemptCount,
                    lastAttemptAt: lastAttemptSeconds.map { Date(timeIntervalSince1970: $0) },
                    lastError: lastError,
                    updatedAt: Date(timeIntervalSince1970: updatedSeconds)
                )
            }
        } ?? []
    }

    static func save(_ items: [SceneOutboxItem], userId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM scene_outbox WHERE user_id = ?",
                arguments: [userKey]
            )
            for item in items {
                try upsert(item, userKey: userKey, db: db)
            }
        }
    }

    static func clear(userId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM scene_outbox WHERE user_id = ?",
                arguments: [userKey]
            )
        }
    }

    static func enqueue(
        scene: SpeakScene,
        userId: UUID,
        outline: SpeakChatOutline? = nil,
        turns: [SpeakTurn] = []
    ) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            let existing = fetchItem(sceneId: scene.id, userId: userId, db: db)
            if var item = existing {
                item.scene = scene
                if let outline {
                    item.outline = outline
                }
                if !turns.isEmpty {
                    item.turns = mergeTurns(existing: item.turns, incoming: turns)
                }
                item.status = .pending
                item.attemptCount = 0
                item.lastAttemptAt = nil
                item.lastError = nil
                item.updatedAt = Date()
                try upsert(item, userKey: userKey, db: db)
            } else {
                let item = SceneOutboxItem(
                    id: scene.id,
                    userId: userId,
                    scene: scene,
                    outline: outline,
                    turns: turns,
                    status: .pending,
                    attemptCount: 0,
                    lastAttemptAt: nil,
                    lastError: nil,
                    updatedAt: Date()
                )
                try upsert(item, userKey: userKey, db: db)
            }
        }
    }

    static func updateAttempt(userId: UUID, sceneId: UUID, error: Error) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: """
                UPDATE scene_outbox
                SET status = ?,
                    attempt_count = attempt_count + 1,
                    last_attempt_at = ?,
                    last_error = ?,
                    updated_at = ?
                WHERE user_id = ? AND scene_id = ?
                """,
                arguments: [
                    SceneOutboxStatus.failed.rawValue,
                    Date().timeIntervalSince1970,
                    error.localizedDescription,
                    Date().timeIntervalSince1970,
                    userKey,
                    sceneId.uuidString
                ]
            )
        }
    }

    static func remove(userId: UUID, sceneId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM scene_outbox WHERE user_id = ? AND scene_id = ?",
                arguments: [userKey, sceneId.uuidString]
            )
        }
    }

    static func pendingSceneIds(userId: UUID) -> Set<UUID> {
        let userKey = LocalStoreKeys.userKey(userId)
        let ids = AppDatabase.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT scene_id FROM scene_outbox WHERE user_id = ?",
                arguments: [userKey]
            ).compactMap { row -> UUID? in
                guard let idString: String = row["scene_id"] else { return nil }
                return UUID(uuidString: idString)
            }
        }
        return Set(ids ?? [])
    }

    static func pendingScenes(userId: UUID) -> [SpeakScene] {
        let userKey = LocalStoreKeys.userKey(userId)
        return AppDatabase.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT scene_json FROM scene_outbox WHERE user_id = ?",
                arguments: [userKey]
            )
            return rows.compactMap { row in
                let sceneJson: String = row["scene_json"]
                return LocalStoreCoders.decode(SpeakScene.self, from: sceneJson)
            }
        } ?? []
    }

    private static func fetchItem(sceneId: UUID, userId: UUID, db: Database) -> SceneOutboxItem? {
        let userKey = LocalStoreKeys.userKey(userId)
        guard let row = try? Row.fetchOne(
            db,
            sql: """
            SELECT scene_id, scene_json, outline_json, turns_json, status,
                   attempt_count, last_attempt_at, last_error, updated_at
            FROM scene_outbox
            WHERE user_id = ? AND scene_id = ?
            """,
            arguments: [userKey, sceneId.uuidString]
        ) else {
            return nil
        }
        guard let id = UUID(uuidString: row["scene_id"]) else { return nil }
        let sceneJson: String = row["scene_json"]
        guard let scene = LocalStoreCoders.decode(SpeakScene.self, from: sceneJson) else { return nil }
        let outlineJson: String? = row["outline_json"]
        let turnsJson: String = row["turns_json"]
        let outline = LocalStoreCoders.decode(SpeakChatOutline.self, from: outlineJson)
        let turns = LocalStoreCoders.decode([SpeakTurn].self, from: turnsJson) ?? []
        let statusRaw: String = row["status"]
        let status = SceneOutboxStatus(rawValue: statusRaw) ?? .pending
        let attemptCount: Int = row["attempt_count"]
        let lastAttemptSeconds: Double? = row["last_attempt_at"]
        let updatedSeconds: Double = row["updated_at"]
        let lastError: String? = row["last_error"]
        return SceneOutboxItem(
            id: id,
            userId: userId,
            scene: scene,
            outline: outline,
            turns: turns,
            status: status,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttemptSeconds.map { Date(timeIntervalSince1970: $0) },
            lastError: lastError,
            updatedAt: Date(timeIntervalSince1970: updatedSeconds)
        )
    }

    private static func upsert(_ item: SceneOutboxItem, userKey: String, db: Database) throws {
        guard let sceneJson = LocalStoreCoders.encode(item.scene),
              let turnsJson = LocalStoreCoders.encode(item.turns)
        else {
            return
        }
        let outlineJson = LocalStoreCoders.encode(item.outline)
        try db.execute(
            sql: """
            INSERT INTO scene_outbox
                (scene_id, user_id, scene_json, outline_json, turns_json, status,
                 attempt_count, last_attempt_at, last_error, updated_at)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(scene_id, user_id) DO UPDATE SET
                scene_json = excluded.scene_json,
                outline_json = excluded.outline_json,
                turns_json = excluded.turns_json,
                status = excluded.status,
                attempt_count = excluded.attempt_count,
                last_attempt_at = excluded.last_attempt_at,
                last_error = excluded.last_error,
                updated_at = excluded.updated_at
            """,
            arguments: [
                item.scene.id.uuidString,
                userKey,
                sceneJson,
                outlineJson,
                turnsJson,
                item.status.rawValue,
                item.attemptCount,
                item.lastAttemptAt?.timeIntervalSince1970,
                item.lastError,
                item.updatedAt.timeIntervalSince1970
            ]
        )
    }

    private static func mergeTurns(existing: [SpeakTurn], incoming: [SpeakTurn]) -> [SpeakTurn] {
        let combined = existing + incoming
        let byStep = Dictionary(combined.map { ($0.step, $0) }, uniquingKeysWith: { _, new in new })
        return byStep.values.sorted { $0.step < $1.step }
    }
}
