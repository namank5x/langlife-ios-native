import Foundation
import Supabase

struct SpeakRepository {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func fetchScenes(for userId: UUID) async throws -> [SpeakScene] {
        try await supabase
            .from("speak_scenes")
            .select("id, title, description, tags, level, created_at")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchScenesCreated(after createdAt: Date, userId: UUID) async throws -> [SpeakScene] {
        let cutoff = Self.iso8601Formatter.string(from: createdAt)
        return try await supabase
            .from("speak_scenes")
            .select("id, title, description, tags, level, created_at")
            .eq("user_id", value: userId.uuidString)
            .gt("created_at", value: cutoff)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}
