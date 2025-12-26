import Foundation

actor SceneSyncService {
    static let shared = SceneSyncService()

    private let writeRepository = SpeakSceneWriteRepository()
    private let baseBackoff: TimeInterval = 10
    private let maxBackoff: TimeInterval = 5 * 60
    private var isSyncing = false

    func syncIfNeeded(userId: UUID) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let items = LocalSceneOutboxStore.load(userId: userId)
        guard !items.isEmpty else { return }

        for item in items {
            guard shouldAttempt(item) else { continue }
            do {
                try await writeRepository.upsertScene(item.scene, userId: userId)
                if let outline = item.outline {
                    try await writeRepository.upsertDetail(
                        sceneId: item.scene.id,
                        userId: userId,
                        outline: outline,
                        turns: item.turns
                    )
                }
                LocalSceneOutboxStore.remove(userId: userId, sceneId: item.scene.id)
            } catch {
                LocalSceneOutboxStore.updateAttempt(userId: userId, sceneId: item.scene.id, error: error)
                if Self.isOffline(error) {
                    break
                }
            }
        }
    }

    private func shouldAttempt(_ item: SceneOutboxItem) -> Bool {
        guard item.attemptCount > 0, let lastAttemptAt = item.lastAttemptAt else {
            return true
        }
        let delay = min(baseBackoff * pow(2, Double(item.attemptCount - 1)), maxBackoff)
        return Date().timeIntervalSince(lastAttemptAt) >= delay
    }

    private static func isOffline(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case URLError.notConnectedToInternet.rawValue,
                 URLError.networkConnectionLost.rawValue,
                 URLError.cannotFindHost.rawValue,
                 URLError.cannotConnectToHost.rawValue,
                 URLError.dnsLookupFailed.rawValue,
                 URLError.timedOut.rawValue:
                return true
            default:
                break
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOffline(underlying)
        }

        return false
    }
}
