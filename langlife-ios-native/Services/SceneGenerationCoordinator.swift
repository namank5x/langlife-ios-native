import Foundation

protocol SceneGenerationProvider {
    func createScene(prompt: String) async throws -> SpeakScene
    func generateScenes(count: Int, excludeTitles: [String], excludeIds: [String]) async throws -> [SpeakScene]
    func generateOutline(scene: SpeakScene) async throws -> (outline: SpeakChatOutline, turns: [SpeakTurn])
    func generateTurn(scene: SpeakScene, outline: SpeakChatOutline, step: Int) async throws -> SpeakTurn
}

enum SceneGenerationError: Error {
    case invalidResponse
}

struct SceneGenerationCoordinator {
    private let serverProvider: SceneGenerationProvider

    init(serverProvider: SceneGenerationProvider = ServerSceneGenerationProvider()) {
        self.serverProvider = serverProvider
    }

    func createScene(
        prompt: String,
        existingTitles: [String]
    ) async throws -> SpeakScene {
        let normalizedExisting = normalizedTitles(existingTitles)
        let scene = try await serverProvider.createScene(prompt: prompt)
        if normalizedExisting.contains(normalize(scene.title)) {
            throw SceneGenerationError.invalidResponse
        }
        return scene
    }

    func generateScenes(
        count: Int,
        excludeTitles: [String],
        excludeIds: [String],
        existingTitles: [String]
    ) async throws -> [SpeakScene] {
        let normalizedExisting = normalizedTitles(existingTitles + excludeTitles)
        let scenes = try await serverProvider.generateScenes(
            count: count,
            excludeTitles: excludeTitles,
            excludeIds: excludeIds
        )

        let filtered = scenes.filter { !normalizedExisting.contains(normalize($0.title)) }
        return Array(filtered.prefix(count))
    }

    func generateOutline(
        scene: SpeakScene
    ) async throws -> (outline: SpeakChatOutline, turns: [SpeakTurn]) {
        try await serverProvider.generateOutline(scene: scene)
    }

    func generateTurn(
        scene: SpeakScene,
        outline: SpeakChatOutline,
        step: Int
    ) async throws -> SpeakTurn {
        try await serverProvider.generateTurn(scene: scene, outline: outline, step: step)
    }

    private func normalizedTitles(_ titles: [String]) -> Set<String> {
        Set(titles.map { normalize($0) })
    }

    private func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
