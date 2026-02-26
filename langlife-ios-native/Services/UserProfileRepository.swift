import Foundation

struct UserProfileRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func syncHSKLevel(_ level: Int) async throws {
        _ = try await apiClient.patchJSON("/api/user/hsk-level", body: HSKLevelBody(hskLevel: level))
    }
}

private struct HSKLevelBody: Encodable {
    let hskLevel: Int
}
