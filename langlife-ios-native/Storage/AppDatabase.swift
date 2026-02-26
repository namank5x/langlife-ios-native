import Foundation
import GRDB

enum AppDatabase {
    static let shared: DatabaseQueue = {
        do {
            let databaseURL = try makeDatabaseURL()
            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }

            #if DEBUG
            var migrator = makeMigrator()
            migrator.eraseDatabaseOnSchemaChange = true
            #else
            let migrator = makeMigrator()
            #endif

            let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try migrator.migrate(queue)
            return queue
        } catch {
            fatalError("Failed to initialize local database: \(error)")
        }
    }()

    static func read<T>(_ block: (Database) throws -> T?) -> T? {
        do {
            return try shared.read(block) ?? nil
        } catch {
            return nil
        }
    }

    static func write(_ block: (Database) throws -> Void) {
        do {
            try shared.write(block)
        } catch {
            assertionFailure("Failed to write to local database: \(error)")
        }
    }

    private static func makeDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL.appendingPathComponent("LangLife", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("app.sqlite")
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createLocalSchema") { db in
            try db.create(table: "flashcards") { table in
                table.column("id", .text).notNull()
                table.column("user_id", .text).notNull()
                table.column("chinese", .text).notNull()
                table.column("pinyin", .text).notNull()
                table.column("english", .text).notNull()
                table.column("example", .text)
                table.column("example_pinyin", .text)
                table.column("example_english", .text)
                table.column("state", .text).notNull()
                table.column("stability", .double).notNull()
                table.column("difficulty", .double).notNull()
                table.column("last_review_at", .double)
                table.column("lapses", .integer).notNull()
                table.column("reps", .integer).notNull()
                table.column("learning_step", .integer).notNull()
                table.column("created_at", .double)
                table.column("updated_at", .double)
                table.primaryKey(["id", "user_id"], onConflict: .replace)
            }

            try db.create(table: "speak_scenes") { table in
                table.column("id", .text).notNull()
                table.column("user_id", .text).notNull()
                table.column("title", .text).notNull()
                table.column("description", .text).notNull()
                table.column("tags", .text).notNull()
                table.column("level", .text).notNull()
                table.column("source", .text)
                table.column("prompt", .text)
                table.column("model", .text)
                table.column("generation_policy", .text)
                table.column("generation_source", .text)
                table.column("created_at", .double)
                table.column("updated_at", .double)
                table.primaryKey(["id", "user_id"], onConflict: .replace)
            }

            try db.create(table: "speak_scene_details") { table in
                table.column("id", .text)
                table.column("user_id", .text).notNull()
                table.column("scene_id", .text).notNull()
                table.column("practice_tip", .text)
                table.column("model", .text)
                table.column("generated_at", .double)
                table.column("outline", .text)
                table.column("outline_turn_count", .integer)
                table.column("outline_model", .text)
                table.column("outline_generated_at", .double)
                table.column("cached_at", .double)
                table.primaryKey(["scene_id", "user_id"], onConflict: .replace)
            }

            try db.create(table: "speak_scene_turns") { table in
                table.column("id", .text).notNull()
                table.column("user_id", .text).notNull()
                table.column("scene_id", .text).notNull()
                table.column("step", .integer).notNull()
                table.column("ai_line", .text).notNull()
                table.column("user_line", .text).notNull()
                table.column("speak_first", .text).notNull()
                table.column("focus_hint", .text)
                table.column("model", .text)
                table.column("generated_at", .double)
                table.primaryKey(["user_id", "scene_id", "step"], onConflict: .replace)
            }

            try db.create(table: "scene_outbox") { table in
                table.column("scene_id", .text).notNull()
                table.column("user_id", .text).notNull()
                table.column("scene_json", .text).notNull()
                table.column("outline_json", .text)
                table.column("turns_json", .text).notNull()
                table.column("status", .text).notNull()
                table.column("attempt_count", .integer).notNull()
                table.column("last_attempt_at", .double)
                table.column("last_error", .text)
                table.column("updated_at", .double).notNull()
                table.primaryKey(["scene_id", "user_id"], onConflict: .replace)
            }

            try db.create(table: "sync_state") { table in
                table.column("entity", .text).notNull()
                table.column("user_id", .text).notNull()
                table.column("last_sync_at", .double).notNull()
                table.column("last_server_created_at", .double)
                table.primaryKey(["entity", "user_id"], onConflict: .replace)
            }

            try db.create(table: "review_limits") { table in
                table.column("user_id", .text).notNull()
                table.column("day_start", .double).notNull()
                table.column("count", .integer).notNull()
                table.primaryKey(["user_id", "day_start"], onConflict: .replace)
            }

            try db.create(index: "speak_scenes_user_created_at", on: "speak_scenes", columns: ["user_id", "created_at"])
            try db.create(index: "speak_scene_details_user_scene", on: "speak_scene_details", columns: ["user_id", "scene_id"])
            try db.create(index: "speak_scene_turns_user_scene_step", on: "speak_scene_turns", columns: ["user_id", "scene_id", "step"], unique: true)
        }
        migrator.registerMigration("addVoiceSessionLimits") { db in
            try db.create(table: "voice_session_limits") { table in
                table.column("user_id", .text).notNull()
                table.column("day_start", .double).notNull()
                table.column("count", .integer).notNull()
                table.primaryKey(["user_id", "day_start"], onConflict: .replace)
            }
        }
        return migrator
    }
}
