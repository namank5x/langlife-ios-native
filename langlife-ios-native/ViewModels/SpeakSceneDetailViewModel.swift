import Combine
import Foundation

@MainActor
final class SpeakSceneDetailViewModel: ObservableObject {
    @Published private(set) var outline: SpeakChatOutline?
    @Published private(set) var turns: [SpeakTurn] = []
    @Published private(set) var isLoadingOutline = false
    @Published private(set) var isLoadingTurn = false
    @Published private(set) var outlineError: String?
    @Published private(set) var turnError: String?

    private let repository: SpeakSceneDetailRepository
    private var prefetchedTurns: [Int: SpeakTurn] = [:]

    init(repository: SpeakSceneDetailRepository = SpeakSceneDetailRepository()) {
        self.repository = repository
    }

    var nextStep: Int? {
        guard let outline else { return nil }
        let existingSteps = Set(turns.map { $0.step })
        let orderedSteps = outline.turns.map { $0.step }.sorted()
        for step in orderedSteps {
            if !existingSteps.contains(step) {
                return step
            }
        }
        return nil
    }

    func loadOutline(scene: SpeakScene) async {
        guard !isLoadingOutline else { return }
        isLoadingOutline = true
        outlineError = nil
        turnError = nil
        turns = []

        defer { isLoadingOutline = false }

        do {
            let result = try await repository.fetchOutline(for: scene)
            if Task.isCancelled { return }
            outline = result.outline
            turns = []
            prefetchedTurns = Dictionary(uniqueKeysWithValues: result.turns.map { ($0.step, $0) })
            if nextStep != nil {
                await loadNextTurn()
            }
        } catch {
            outlineError = mapErrorMessage(error, fallback: "Unable to load the scene outline.")
            outline = nil
            turns = []
            prefetchedTurns = [:]
        }
    }

    func loadNextTurn() async {
        guard let outline else { return }
        guard let step = nextStep else { return }
        guard !isLoadingTurn else { return }

        isLoadingTurn = true
        turnError = nil
        defer { isLoadingTurn = false }

        if let cached = prefetchedTurns[step] {
            prefetchedTurns[step] = nil
            turns = mergeTurns(existing: turns, incoming: cached)
            return
        }

        do {
            let turn = try await repository.fetchTurn(sceneId: outline.sceneId, step: step)
            if Task.isCancelled { return }
            turns = mergeTurns(existing: turns, incoming: turn)
        } catch {
            turnError = mapErrorMessage(error, fallback: "Unable to load the next turn.")
        }
    }

    private func mapErrorMessage(_ error: Error, fallback: String) -> String {
        guard let apiError = error as? APIClientError else {
            return fallback
        }

        switch apiError {
        case .httpError(let statusCode):
            switch statusCode {
            case 401:
                return "Scene not available right now."
            case 404:
                return "Scene not found. Try another one."
            case 409:
                return "Outline missing. Try opening the scene again."
            case 504:
                return "This is taking too long. Try again in a moment."
            default:
                return fallback
            }
        }
    }

    private func sortTurns(_ list: [SpeakTurn]) -> [SpeakTurn] {
        list.sorted { $0.step < $1.step }
    }

    private func mergeTurns(existing: [SpeakTurn], incoming: SpeakTurn) -> [SpeakTurn] {
        let remaining = existing.filter { $0.step != incoming.step }
        return sortTurns(remaining + [incoming])
    }

}
