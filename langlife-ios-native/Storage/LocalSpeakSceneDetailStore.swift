import Foundation
import GRDB

struct SpeakSceneDetailCache: Codable {
    let outline: SpeakChatOutline
    let turns: [SpeakTurn]
    let cachedAt: Date
}

enum LocalSpeakSceneDetailStore {
    private static let maxEntries = 50

    static func load(userId: UUID, sceneId: UUID) -> SpeakSceneDetailCache? {
        let userKey = LocalStoreKeys.userKey(userId)
        let cache = AppDatabase.read { db -> SpeakSceneDetailCache? in
            guard let detailRow = try Row.fetchOne(
                db,
                sql: """
                SELECT practice_tip, outline, cached_at
                FROM speak_scene_details
                WHERE user_id = ? AND scene_id = ?
                """,
                arguments: [userKey, sceneId.uuidString]
            ) else {
                return nil
            }

            guard let outlineJson: String = detailRow["outline"],
                  let outlineTurns = LocalStoreCoders.decode([SpeakTurnOutline].self, from: outlineJson)
            else {
                return nil
            }

            let practiceTip: String? = detailRow["practice_tip"]
            let outline = SpeakChatOutline(
                sceneId: sceneId,
                turns: outlineTurns,
                practiceTip: practiceTip
            )

            let cachedAtSeconds: Double? = detailRow["cached_at"]
            let cachedAt = cachedAtSeconds.map { Date(timeIntervalSince1970: $0) } ?? Date()

            let turnRows = try Row.fetchAll(
                db,
                sql: """
                SELECT step, ai_line, user_line, speak_first, focus_hint
                FROM speak_scene_turns
                WHERE user_id = ? AND scene_id = ?
                ORDER BY step ASC
                """,
                arguments: [userKey, sceneId.uuidString]
            )

            let turns = turnRows.compactMap { row -> SpeakTurn? in
                let step: Int = row["step"]
                guard let aiLineJson: String = row["ai_line"],
                      let userLineJson: String = row["user_line"],
                      let aiLine = LocalStoreCoders.decode(SpeakLine.self, from: aiLineJson),
                      let userLine = LocalStoreCoders.decode(SpeakLine.self, from: userLineJson)
                else {
                    return nil
                }
                let speakFirstRaw: String = row["speak_first"]
                guard let speakFirst = SpeakRole(rawValue: speakFirstRaw) else { return nil }
                let focusHint: String? = row["focus_hint"]
                return SpeakTurn(
                    step: step,
                    aiLine: aiLine,
                    userLine: userLine,
                    speakFirst: speakFirst,
                    focusHint: focusHint
                )
            }

            return SpeakSceneDetailCache(outline: outline, turns: turns, cachedAt: cachedAt)
        }
        if cache != nil {
            AppDatabase.write { db in
                touch(db: db, userKey: userKey, sceneId: sceneId, cachedAt: Date())
            }
        }
        return cache
    }

    static func save(_ cache: SpeakSceneDetailCache, userId: UUID, sceneId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            guard let outlineJson = LocalStoreCoders.encode(cache.outline.turns) else { return }
            let cachedAt = cache.cachedAt.timeIntervalSince1970

            try db.execute(
                sql: """
                INSERT INTO speak_scene_details
                    (id, user_id, scene_id, practice_tip, outline, outline_turn_count,
                     outline_generated_at, cached_at)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(scene_id, user_id) DO UPDATE SET
                    practice_tip = excluded.practice_tip,
                    outline = excluded.outline,
                    outline_turn_count = excluded.outline_turn_count,
                    outline_generated_at = excluded.outline_generated_at,
                    cached_at = excluded.cached_at
                """,
                arguments: [
                    sceneId.uuidString,
                    userKey,
                    sceneId.uuidString,
                    cache.outline.practiceTip,
                    outlineJson,
                    cache.outline.turns.count,
                    cachedAt,
                    cachedAt
                ]
            )

            try db.execute(
                sql: "DELETE FROM speak_scene_turns WHERE user_id = ? AND scene_id = ?",
                arguments: [userKey, sceneId.uuidString]
            )

            for turn in cache.turns {
                guard let aiLineJson = LocalStoreCoders.encode(turn.aiLine),
                      let userLineJson = LocalStoreCoders.encode(turn.userLine)
                else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO speak_scene_turns
                        (id, user_id, scene_id, step, ai_line, user_line, speak_first, focus_hint, generated_at)
                    VALUES
                        (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        "\(sceneId.uuidString)-\(turn.step)",
                        userKey,
                        sceneId.uuidString,
                        turn.step,
                        aiLineJson,
                        userLineJson,
                        turn.speakFirst.rawValue,
                        turn.focusHint,
                        cachedAt
                    ]
                )
            }

            enforceLimit(db: db, userKey: userKey)
        }
    }

    static func clear(userId: UUID, sceneId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM speak_scene_details WHERE user_id = ? AND scene_id = ?",
                arguments: [userKey, sceneId.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM speak_scene_turns WHERE user_id = ? AND scene_id = ?",
                arguments: [userKey, sceneId.uuidString]
            )
        }
    }

    static func clearAll(userId: UUID) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM speak_scene_details WHERE user_id = ?",
                arguments: [userKey]
            )
            try db.execute(
                sql: "DELETE FROM speak_scene_turns WHERE user_id = ?",
                arguments: [userKey]
            )
        }
    }

    private static func touch(db: Database, userKey: String, sceneId: UUID, cachedAt: Date) {
        try? db.execute(
            sql: """
            UPDATE speak_scene_details
            SET cached_at = ?
            WHERE user_id = ? AND scene_id = ?
            """,
            arguments: [cachedAt.timeIntervalSince1970, userKey, sceneId.uuidString]
        )
    }

    private static func enforceLimit(db: Database, userKey: String) {
        guard maxEntries > 0 else { return }
        let rows = (try? Row.fetchAll(
            db,
            sql: """
            SELECT scene_id
            FROM speak_scene_details
            WHERE user_id = ?
            ORDER BY cached_at ASC
            """,
            arguments: [userKey]
        )) ?? []

        guard rows.count > maxEntries else { return }
        let overflow = rows.count - maxEntries
        let toRemove = rows.prefix(overflow).compactMap { row -> String? in
            row["scene_id"]
        }
        for sceneId in toRemove {
            try? db.execute(
                sql: "DELETE FROM speak_scene_details WHERE user_id = ? AND scene_id = ?",
                arguments: [userKey, sceneId]
            )
            try? db.execute(
                sql: "DELETE FROM speak_scene_turns WHERE user_id = ? AND scene_id = ?",
                arguments: [userKey, sceneId]
            )
        }
    }
}
