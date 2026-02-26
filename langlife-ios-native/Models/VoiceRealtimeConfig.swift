import Foundation

struct RealtimeTokenResponse: Decodable {
    let clientSecret: String
    let expiresAt: String
}

struct RealtimePromptResponse {
    let instructions: String
    let tools: [[String: Any]]

    static func parse(_ data: Data) throws -> RealtimePromptResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instructions = json["instructions"] as? String else {
            throw RealtimeConfigError.invalidResponse
        }
        let tools = (json["tools"] as? [[String: Any]]) ?? []
        return RealtimePromptResponse(instructions: instructions, tools: tools)
    }
}

enum RealtimeConfigError: Error {
    case invalidResponse
}
