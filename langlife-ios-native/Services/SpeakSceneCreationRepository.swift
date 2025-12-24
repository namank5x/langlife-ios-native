import Foundation

struct SpeakSceneCreationRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func createScene(prompt: String) async throws -> SpeakScene {
        let request = CreateSceneRequest(prompt: prompt)
        let data = try await apiClient.postJSON("/api/scenes", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(CreateSceneResponse.self, from: data)
        return response.scene
    }
}

private struct CreateSceneRequest: Encodable {
    let prompt: String
}

private struct CreateSceneResponse: Decodable {
    let scene: SpeakScene
}
