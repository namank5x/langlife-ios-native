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

    func get(_ path: String) async throws -> Data {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "GET"

        if let token = await accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw APIClientError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    func patchJSON<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "PATCH"
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

    func delete(_ path: String) async throws -> Data {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(normalizedPath))
        request.httpMethod = "DELETE"

        if let token = await accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw APIClientError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }
}

enum APIClientError: LocalizedError {
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode):
            switch statusCode {
            case 401:
                return "Authentication required. Please sign in again."
            case 404:
                return "Service not available (404)."
            case 500...599:
                return "Server error (\(statusCode)). Please try again."
            default:
                return "Request failed with status \(statusCode)."
            }
        }
    }
}
