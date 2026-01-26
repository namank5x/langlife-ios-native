import Foundation

struct SpeakSceneDetailRepository {
    private let generator = SceneGenerationCoordinator()

    func fetchOutline(for scene: SpeakScene, userId: UUID?) async throws -> (outline: SpeakChatOutline, turns: [SpeakTurn]) {
        if userId == nil, let content = DefaultSpeakContent.content(for: scene.id) {
            return (content.outline, content.turns)
        }

        let result = try await generator.generateOutline(scene: scene)
        if let userId {
            LocalSceneOutboxStore.enqueue(
                scene: scene,
                userId: userId,
                outline: result.outline,
                turns: result.turns
            )
            Task {
                await SceneSyncService.shared.syncIfNeeded(userId: userId)
            }
        }
        return result
    }

    func fetchTurn(
        scene: SpeakScene,
        outline: SpeakChatOutline,
        step: Int,
        userId: UUID?
    ) async throws -> SpeakTurn {
        if userId == nil,
           let turn = DefaultSpeakContent.content(for: scene.id)?.turns.first(where: { $0.step == step }) {
            return turn
        }

        let turn = try await generator.generateTurn(
            scene: scene,
            outline: outline,
            step: step
        )
        if let userId {
            LocalSceneOutboxStore.enqueue(
                scene: scene,
                userId: userId,
                outline: outline,
                turns: [turn]
            )
            Task {
                await SceneSyncService.shared.syncIfNeeded(userId: userId)
            }
        }
        return turn
    }
}
