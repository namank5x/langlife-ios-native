import Foundation

struct SpeakSceneGenerationRepository {
    private let generator = SceneGenerationCoordinator()

    func generateScenes(
        count: Int,
        excludeIds: [String],
        existingTitles: [String],
        userId: UUID?
    ) async throws -> [SpeakScene] {
        let scenes = try await generator.generateScenes(
            count: count,
            excludeTitles: existingTitles,
            excludeIds: excludeIds,
            existingTitles: existingTitles
        )
        if let userId {
            for scene in scenes {
                LocalSceneOutboxStore.enqueue(scene: scene, userId: userId)
            }
            Task {
                await SceneSyncService.shared.syncIfNeeded(userId: userId)
            }
        }
        return scenes
    }
}
