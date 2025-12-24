import Foundation

struct SpeakSceneGenerationRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func generateScenes(count: Int, excludeIds: [String]) async throws -> [SpeakScene] {
        let request = GenerateSceneRequest(count: count, excludeIds: excludeIds)
        let data = try await apiClient.postJSON("/api/scenes/generate", body: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(GenerateSceneResponse.self, from: data)
        return response.scenes
    }
}

private struct GenerateSceneRequest: Encodable {
    let count: Int
    let excludeIds: [String]
}

private struct GenerateSceneResponse: Decodable {
    let scenes: [SpeakScene]
}
