import Foundation
import Supabase

struct SpeakSceneWriteRepository {
    func upsertScene(_ scene: SpeakScene, userId: UUID) async throws {
        let record = SpeakSceneRecord(
            id: scene.id,
            userId: userId,
            title: scene.title,
            description: scene.description,
            tags: scene.tags,
            level: scene.level,
            createdAt: scene.createdAt ?? Date()
        )
        _ = try await supabase
            .from("speak_scenes")
            .upsert(record, onConflict: "id")
            .execute()
    }

    func upsertDetail(
        sceneId: UUID,
        userId: UUID,
        outline: SpeakChatOutline,
        turns: [SpeakTurn]
    ) async throws {
        let record = SpeakSceneDetailRecord(
            sceneId: sceneId,
            userId: userId,
            outline: outline,
            turns: turns,
            updatedAt: Date()
        )
        _ = try await supabase
            .from("speak_scene_details")
            .upsert(record, onConflict: "scene_id")
            .execute()
    }
}

private struct SpeakSceneRecord: Encodable {
    let id: UUID
    let userId: UUID
    let title: String
    let description: String
    let tags: [String]
    let level: SpeakScene.Level
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case tags
        case level
        case createdAt = "created_at"
    }
}

private struct SpeakSceneDetailRecord: Encodable {
    let sceneId: UUID
    let userId: UUID
    let outline: SpeakChatOutline
    let turns: [SpeakTurn]
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case sceneId = "scene_id"
        case userId = "user_id"
        case outline
        case turns
        case updatedAt = "updated_at"
    }
}
