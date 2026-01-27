import Foundation

enum LocalUserDataStore {
    static func clearAll(userId: UUID) {
        LocalFlashcardStore.clear(userId: userId)
        LocalSpeakSceneStore.clear(userId: userId)
        LocalSpeakSceneDetailStore.clearAll(userId: userId)
        LocalSceneOutboxStore.clear(userId: userId)
        LocalReviewLimitStore.clear(userId: userId)
    }
}
