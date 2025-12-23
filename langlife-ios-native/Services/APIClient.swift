import Foundation

struct APIClient {
    let baseURL: URL
    let accessTokenProvider: @MainActor () -> String?

    init(
        baseURL: URL = AppConfig.apiBaseURL,
        accessTokenProvider: @escaping @MainActor () -> String? = { AuthManager.shared.accessToken }
    ) {
        self.baseURL = baseURL
        self.accessTokenProvider = accessTokenProvider
    }

    func postJSON<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw APIClientError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }
}

enum APIClientError: Error {
    case httpError(statusCode: Int)
}
