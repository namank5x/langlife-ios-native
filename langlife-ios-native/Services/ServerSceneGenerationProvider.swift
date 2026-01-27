import Foundation

struct ServerSceneGenerationProvider: SceneGenerationProvider {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func createScene(prompt: String) async throws -> SpeakScene {
        let request = CreateSceneRequest(prompt: prompt)
        let data = try await apiClient.postJSON("/api/scenes", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom(ISO8601DateDecoder.decode)
        let response = try decoder.decode(CreateSceneResponse.self, from: data)
        return response.scene
    }

    func generateScenes(count: Int, excludeTitles: [String], excludeIds: [String]) async throws -> [SpeakScene] {
        let _ = excludeTitles
        let request = GenerateSceneRequest(count: count, excludeIds: excludeIds)
        let data = try await apiClient.postJSON("/api/scenes/generate", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom(ISO8601DateDecoder.decode)
        let response = try decoder.decode(GenerateSceneResponse.self, from: data)
        return response.scenes
    }

    func generateOutline(scene: SpeakScene) async throws -> (outline: SpeakChatOutline, turns: [SpeakTurn]) {
        let request = OutlineRequest(scene: scene)
        let data = try await apiClient.postJSON("/api/scenes/outline", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeakOutlineResponse.self, from: data)
        return (response.outline, response.turns ?? [])
    }

    func generateTurn(scene: SpeakScene, outline: SpeakChatOutline, step: Int) async throws -> SpeakTurn {
        let _ = outline
        let request = TurnRequest(sceneId: scene.id, step: step)
        let data = try await apiClient.postJSON("/api/scenes/turn", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeakTurnResponse.self, from: data)
        return response.turn
    }
}

private struct CreateSceneRequest: Encodable {
    let prompt: String
}

private struct CreateSceneResponse: Decodable {
    let scene: SpeakScene
}

private struct GenerateSceneRequest: Encodable {
    let count: Int
    let excludeIds: [String]
}

private struct GenerateSceneResponse: Decodable {
    let scenes: [SpeakScene]
}

private struct OutlineRequest: Encodable {
    let scene: SpeakScene
}

private struct TurnRequest: Encodable {
    let sceneId: UUID
    let step: Int
}

private struct SpeakOutlineResponse: Decodable {
    let outline: SpeakChatOutline
    let turns: [SpeakTurn]?
}

private struct SpeakTurnResponse: Decodable {
    let turn: SpeakTurn
}
