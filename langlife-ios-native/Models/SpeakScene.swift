import Foundation

struct SpeakScene: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let tags: [String]
    let level: Level
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case tags
        case level
        case createdAt = "created_at"
    }

    enum Level: String, Codable {
        case beginner
        case intermediate
        case advanced
    }
}
