import Foundation

struct SpeakSceneCreationRepository {
    private let generator = SceneGenerationCoordinator()

    func createScene(
        prompt: String,
        existingTitles: [String],
        userId: UUID?
    ) async throws -> SpeakScene {
        let scene = try await generator.createScene(
            prompt: prompt,
            existingTitles: existingTitles
        )
        if let userId {
            LocalSceneOutboxStore.enqueue(scene: scene, userId: userId)
            Task {
                await SceneSyncService.shared.syncIfNeeded(userId: userId)
            }
        }
        return scene
    }
}
