import Combine
import Foundation
import os

@MainActor
final class SpeakSceneStore: ObservableObject {
    @Published private(set) var scenes: [SpeakScene] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository = SpeakRepository()
    private var lastLoadedUserId: UUID?
    private var isRefreshing = false
    private let syncTTL: TimeInterval = 10 * 60
    private static let offlineMessage = "Offline. Sync will resume later."
    private static let loadFailureMessage = "Could not load scenes right now."
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "langlife-ios-native",
        category: "SpeakSceneStore"
    )

    var isOfflineNotice: Bool {
        errorMessage == Self.offlineMessage
    }

    func loadIfNeeded(for userId: UUID?) async {
        if isRefreshing, lastLoadedUserId == userId { return }
        if let userId {
            if lastLoadedUserId != userId || scenes.isEmpty {
                scenes = []
                loadCachedScenes(for: userId)
                if scenes.isEmpty {
                    scenes = pendingScenes(for: userId)
                }
                lastLoadedUserId = userId
            }
            await refreshIfStale(for: userId)
            return
        }

        errorMessage = nil
        clearUserCacheIfNeeded()
        scenes = []
    }

    func refresh(for userId: UUID?) async {
        if isRefreshing, lastLoadedUserId == userId { return }
        guard let userId else {
            errorMessage = nil
            scenes = []
            return
        }

        await refreshIfStale(for: userId, force: true)
    }

    func upsertScene(_ scene: SpeakScene, userId: UUID) {
        let resolvedScene = scene.createdAt == nil
            ? SpeakScene(
                id: scene.id,
                title: scene.title,
                description: scene.description,
                tags: scene.tags,
                level: scene.level,
                createdAt: Date()
            )
            : scene
        if let index = scenes.firstIndex(where: { $0.id == resolvedScene.id }) {
            scenes[index] = resolvedScene
        } else {
            scenes.insert(resolvedScene, at: 0)
        }
        LocalSpeakSceneStore.save(scenes, userId: userId)
        touchSyncState(userId: userId)
    }

    func removeScene(id: UUID, userId: UUID?) {
        scenes.removeAll { $0.id == id }
        if let userId {
            LocalSpeakSceneStore.save(scenes, userId: userId)
            LocalSpeakSceneDetailStore.clear(userId: userId, sceneId: id)
            LocalSceneOutboxStore.remove(userId: userId, sceneId: id)
            touchSyncState(userId: userId)
        }
    }

    private func refreshIfStale(for userId: UUID, force: Bool = false) async {
        let hadError = errorMessage != nil
        errorMessage = nil
        let syncState = LocalSpeakSceneStore.loadSyncState(userId: userId)
        if !force, let syncState {
            let age = Date().timeIntervalSince(syncState.lastSyncAt)
            if age < syncTTL, !hadError { return }
        }

        await refreshFromServer(for: userId, syncState: syncState)
    }

    private func refreshFromServer(for userId: UUID, syncState: SpeakSceneSyncState?) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = scenes.isEmpty
        defer {
            isRefreshing = false
            isLoading = false
        }

        errorMessage = nil
        lastLoadedUserId = userId

        do {
            if let lastServerCreatedAt = syncState?.lastServerCreatedAt {
                let newScenes = try await repository.fetchScenesCreated(
                    after: lastServerCreatedAt,
                    userId: userId
                )
                guard lastLoadedUserId == userId else { return }
                if !newScenes.isEmpty {
                    mergeNewScenes(newScenes)
                    LocalSpeakSceneStore.save(scenes, userId: userId)
                }
                let maxCreatedAt = [lastServerCreatedAt, newScenes.compactMap(\.createdAt).max()]
                    .compactMap { $0 }
                    .max()
                updateSyncState(userId: userId, lastServerCreatedAt: maxCreatedAt)
                return
            }

            let fetchedScenes = try await repository.fetchScenes(for: userId)
            guard lastLoadedUserId == userId else { return }
            if fetchedScenes.isEmpty {
                scenes = pendingScenes(for: userId)
                LocalSpeakSceneStore.save(scenes, userId: userId)
                updateSyncState(userId: userId, lastServerCreatedAt: nil)
                return
            }

            scenes = mergeWithPendingScenes(fetchedScenes, userId: userId)
            LocalSpeakSceneStore.save(scenes, userId: userId)
            let maxCreatedAt = fetchedScenes.compactMap(\.createdAt).max()
            updateSyncState(userId: userId, lastServerCreatedAt: maxCreatedAt)
        } catch {
            if error.isCancelled {
                return
            }
            Self.logger.error("Failed to refresh scenes: \(error.diagnosticDescription, privacy: .public)")
            errorMessage = mapRefreshError(error)
            if scenes.isEmpty {
                loadCachedScenes(for: userId)
                if scenes.isEmpty {
                    scenes = pendingScenes(for: userId)
                }
            }
        }
    }

    private func mapRefreshError(_ error: Error) -> String {
        if error.isOffline {
            return Self.offlineMessage
        }

        #if DEBUG
        return "\(Self.loadFailureMessage) (\(error.diagnosticDescription))"
        #else
        return Self.loadFailureMessage
        #endif
    }

    private func loadCachedScenes(for userId: UUID) {
        if let local = LocalSpeakSceneStore.load(userId: userId), !local.isEmpty {
            scenes = local
        }
    }

    private func mergeNewScenes(_ newScenes: [SpeakScene]) {
        guard !newScenes.isEmpty else { return }
        var updatedScenes = scenes
        let existingIndex = Dictionary(
            uniqueKeysWithValues: updatedScenes.enumerated().map { ($0.element.id, $0.offset) }
        )
        var toPrepend: [SpeakScene] = []
        for scene in newScenes {
            if let index = existingIndex[scene.id] {
                updatedScenes[index] = scene
            } else {
                toPrepend.append(scene)
            }
        }
        if !toPrepend.isEmpty {
            updatedScenes = toPrepend + updatedScenes
        }
        scenes = updatedScenes
    }

    private func mergeWithPendingScenes(_ remoteScenes: [SpeakScene], userId: UUID) -> [SpeakScene] {
        let pending = pendingScenes(for: userId)
        guard !pending.isEmpty else { return remoteScenes }
        let remoteById = Set(remoteScenes.map { $0.id })
        let pendingOnly = pending.filter { !remoteById.contains($0.id) }
        return pendingOnly + remoteScenes
    }

    private func pendingScenes(for userId: UUID) -> [SpeakScene] {
        LocalSceneOutboxStore.pendingScenes(userId: userId)
    }

    private func updateSyncState(userId: UUID, lastServerCreatedAt: Date?) {
        let state = SpeakSceneSyncState(
            lastSyncAt: Date(),
            lastServerCreatedAt: lastServerCreatedAt
        )
        LocalSpeakSceneStore.saveSyncState(state, userId: userId)
    }

    private func touchSyncState(userId: UUID) {
        let lastServerCreatedAt = LocalSpeakSceneStore.loadSyncState(userId: userId)?.lastServerCreatedAt
        updateSyncState(userId: userId, lastServerCreatedAt: lastServerCreatedAt)
    }

    private func clearUserCacheIfNeeded() {
        guard let loadedUserId = lastLoadedUserId else { return }
        LocalSpeakSceneStore.clear(userId: loadedUserId)
        LocalSpeakSceneDetailStore.clearAll(userId: loadedUserId)
        lastLoadedUserId = nil
        scenes = []
    }
}
