import Foundation

struct SpeakSceneDetailRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func fetchOutline(for scene: SpeakScene) async throws -> (outline: SpeakChatOutline, turns: [SpeakTurn]) {
        let request = OutlineRequest(scene: scene)
        let data = try await apiClient.postJSON("/api/scenes/outline", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeakOutlineResponse.self, from: data)
        return (response.outline, response.turns ?? [])
    }

    func fetchTurn(sceneId: UUID, step: Int) async throws -> SpeakTurn {
        let request = TurnRequest(sceneId: sceneId, step: step)
        let data = try await apiClient.postJSON("/api/scenes/turn", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeakTurnResponse.self, from: data)
        return response.turn
    }
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
