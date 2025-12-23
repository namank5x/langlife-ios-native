import Foundation

struct SpeakScene: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let tags: [String]
    let level: Level

    enum Level: String, Codable {
        case beginner
        case intermediate
        case advanced
    }
}
