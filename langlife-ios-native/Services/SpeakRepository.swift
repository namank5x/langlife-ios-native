import Foundation
import Supabase

struct SpeakRepository {
    func fetchScenes(for userId: UUID) async throws -> [SpeakScene] {
        try await supabase
            .from("speak_scenes")
            .select("id, title, description, tags, level")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}
