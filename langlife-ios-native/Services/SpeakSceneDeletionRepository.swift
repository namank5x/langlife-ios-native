import Foundation

struct SpeakSceneDeletionRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func deleteScene(id: UUID) async throws {
        _ = try await apiClient.delete("/api/scenes/\(id.uuidString)")
    }
}
