import Foundation

struct AccountDeletionRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func deleteAccount() async throws {
        _ = try await apiClient.delete("/api/account")
    }
}
