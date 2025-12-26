import Foundation
import Supabase
import os

struct SpeakRepository {
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "langlife-ios-native",
        category: "SpeakRepository"
    )

    func fetchScenes(for userId: UUID) async throws -> [SpeakScene] {
        let payloads: [SpeakScenePayload] = try await supabase
            .from("speak_scenes")
            .select("id, title, description, tags, level, created_at")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return payloads.map(Self.scene(from:))
    }

    func fetchScenesCreated(after createdAt: Date, userId: UUID) async throws -> [SpeakScene] {
        let cutoff = Self.iso8601Formatter.string(from: createdAt)
        let payloads: [SpeakScenePayload] = try await supabase
            .from("speak_scenes")
            .select("id, title, description, tags, level, created_at")
            .eq("user_id", value: userId.uuidString)
            .gt("created_at", value: cutoff)
            .order("created_at", ascending: false)
            .execute()
            .value
        return payloads.map(Self.scene(from:))
    }

    private static func scene(from payload: SpeakScenePayload) -> SpeakScene {
        let resolvedLevel = SpeakScene.Level(rawValue: payload.level ?? "") ?? .beginner
        if let level = payload.level, SpeakScene.Level(rawValue: level) == nil {
            logger.warning("Unknown scene level '\(level, privacy: .public)' for scene \(payload.id, privacy: .public)")
        }
        let resolvedTags = payload.tags?.resolvedTags(logger: logger, sceneId: payload.id) ?? []
        return SpeakScene(
            id: payload.id,
            title: payload.title,
            description: payload.description ?? "",
            tags: resolvedTags,
            level: resolvedLevel,
            createdAt: payload.createdAt
        )
    }
}

private struct SpeakScenePayload: Decodable {
    let id: UUID
    let title: String
    let description: String?
    let tags: SceneTagsPayload?
    let level: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case tags
        case level
        case createdAt = "created_at"
    }
}

private enum SceneTagsPayload: Decodable {
    case array([String])
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        self = .array([])
    }

    func resolvedTags(logger: Logger, sceneId: UUID) -> [String] {
        switch self {
        case .array(let tags):
            return tags
        case .string(let raw):
            if let data = raw.data(using: .utf8),
               let tags = try? JSONDecoder().decode([String].self, from: data) {
                return tags
            }
            if !raw.isEmpty {
                logger.warning("Unable to decode tags '\(raw, privacy: .public)' for scene \(sceneId, privacy: .public)")
            }
            return []
        }
    }
}
