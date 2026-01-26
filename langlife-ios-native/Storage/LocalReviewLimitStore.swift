import Foundation
import GRDB

enum LocalReviewLimitStore {
    static func clear(userId: UUID?) {
        let userKey = LocalStoreKeys.userKey(userId)
        AppDatabase.write { db in
            try db.execute(
                sql: "DELETE FROM review_limits WHERE user_id = ?",
                arguments: [userKey]
            )
        }
    }

    static func loadCount(userId: UUID?, dayStart: Date) -> Int {
        let userKey = LocalStoreKeys.userKey(userId)
        let dayStartSeconds = dayStart.timeIntervalSince1970
        return AppDatabase.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT count FROM review_limits WHERE user_id = ? AND day_start = ?",
                arguments: [userKey, dayStartSeconds]
            )
            guard let row else { return nil }
            let count: Int = row["count"]
            return count
        } ?? 0
    }

    @discardableResult
    static func incrementCount(userId: UUID?, dayStart: Date) -> Int {
        let userKey = LocalStoreKeys.userKey(userId)
        let dayStartSeconds = dayStart.timeIntervalSince1970
        var newCount = 1

        AppDatabase.write { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT count FROM review_limits WHERE user_id = ? AND day_start = ?",
                arguments: [userKey, dayStartSeconds]
            )
            let currentCount: Int
            if let row {
                currentCount = row["count"]
            } else {
                currentCount = 0
            }
            newCount = currentCount + 1
            try db.execute(
                sql: """
                INSERT INTO review_limits (user_id, day_start, count)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id, day_start) DO UPDATE SET
                    count = excluded.count
                """,
                arguments: [userKey, dayStartSeconds, newCount]
            )
        }

        return newCount
    }
}
