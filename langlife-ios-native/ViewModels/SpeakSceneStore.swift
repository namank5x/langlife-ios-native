import Combine
import Foundation

@MainActor
final class SpeakSceneStore: ObservableObject {
    @Published private(set) var scenes: [SpeakScene] = SpeakSceneSeed.defaults
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository = SpeakRepository()
    private var lastLoadedUserId: UUID?
    private var isRefreshing = false
    private let syncTTL: TimeInterval = 10 * 60
    private static let offlineMessage = "Offline. Sync will resume later."

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
                    scenes = SpeakSceneSeed.defaults
                }
                lastLoadedUserId = userId
            }
            await refreshIfStale(for: userId)
            return
        }

        errorMessage = nil
        clearUserCacheIfNeeded()
        scenes = SpeakSceneSeed.defaults
    }

    func refresh(for userId: UUID?) async {
        if isRefreshing, lastLoadedUserId == userId { return }
        guard let userId else {
            errorMessage = nil
            scenes = SpeakSceneSeed.defaults
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
        if scenes.isEmpty {
            scenes = SpeakSceneSeed.defaults
        }
        if let userId {
            LocalSpeakSceneStore.save(scenes, userId: userId)
            LocalSpeakSceneDetailStore.clear(userId: userId, sceneId: id)
            touchSyncState(userId: userId)
        }
    }

    private func refreshIfStale(for userId: UUID, force: Bool = false) async {
        let syncState = LocalSpeakSceneStore.loadSyncState(userId: userId)
        if !force, let syncState {
            let age = Date().timeIntervalSince(syncState.lastSyncAt)
            if age < syncTTL { return }
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
                scenes = SpeakSceneSeed.defaults
                LocalSpeakSceneStore.save(scenes, userId: userId)
                updateSyncState(userId: userId, lastServerCreatedAt: nil)
                return
            }

            scenes = fetchedScenes
            LocalSpeakSceneStore.save(scenes, userId: userId)
            let maxCreatedAt = fetchedScenes.compactMap(\.createdAt).max()
            updateSyncState(userId: userId, lastServerCreatedAt: maxCreatedAt)
        } catch {
            errorMessage = error.isOffline
                ? Self.offlineMessage
                : "Could not load scenes right now."
            if scenes.isEmpty || scenes == SpeakSceneSeed.defaults {
                loadCachedScenes(for: userId)
                if scenes.isEmpty {
                    scenes = SpeakSceneSeed.defaults
                }
            }
        }
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
