import Foundation

enum LocalStoreKeys {
    static let anonymousUserId = "__local__"

    static func userKey(_ userId: UUID?) -> String {
        userId?.uuidString ?? anonymousUserId
    }
}
