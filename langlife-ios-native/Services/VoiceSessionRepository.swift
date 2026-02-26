import Foundation

struct VoiceSessionRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func fetchToken() async throws -> RealtimeTokenResponse {
        let data = try await apiClient.postJSON("/api/realtime/token", body: EmptyBody())
        return try JSONDecoder().decode(RealtimeTokenResponse.self, from: data)
    }

    func fetchPrompt() async throws -> RealtimePromptResponse {
        let data = try await apiClient.get("/api/realtime/prompt")
        return try RealtimePromptResponse.parse(data)
    }

    func completeSession(_ request: VoiceSessionCompleteRequest) async throws -> VoiceSessionCompleteResponse {
        let data = try await apiClient.postJSON("/api/realtime/sessions", body: request)
        return try JSONDecoder().decode(VoiceSessionCompleteResponse.self, from: data)
    }
}

private struct EmptyBody: Encodable {}
