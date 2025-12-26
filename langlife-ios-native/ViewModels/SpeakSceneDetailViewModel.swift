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
    @Published private(set) var speechAttempts: [SpeechKey: SpeechAttempt] = [:]
    @Published private(set) var activeSpeechKey: SpeechKey?
    @Published private(set) var latestLoadedTurnStep: Int?

    private let repository: SpeakSceneDetailRepository
    private var prefetchedTurns: [Int: SpeakTurn] = [:]
    private var currentUserId: UUID?
    private var currentSceneId: UUID?
    private var currentScene: SpeakScene?
    private let cacheTTL: TimeInterval = 24 * 60 * 60

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

    func loadOutline(scene: SpeakScene, userId: UUID?) async {
        guard !isLoadingOutline else { return }
        currentUserId = userId
        currentSceneId = scene.id
        currentScene = scene
        isLoadingOutline = true
        outlineError = nil
        turnError = nil
        speechAttempts = [:]
        activeSpeechKey = nil
        latestLoadedTurnStep = nil
        prefetchedTurns = [:]

        let cachedDetail = loadCachedDetail(userId: userId, sceneId: scene.id)
        let cacheAge = cachedDetail.map { Date().timeIntervalSince($0.cachedAt) }
        let hasFreshCache = cacheAge.map { $0 < cacheTTL } ?? false

        if let cachedDetail {
            outline = cachedDetail.outline
            turns = []
            prefetchedTurns = Dictionary(uniqueKeysWithValues: cachedDetail.turns.map { ($0.step, $0) })
        } else {
            outline = nil
            turns = []
            prefetchedTurns = [:]
        }

        defer { isLoadingOutline = false }

        if turns.isEmpty, nextStep != nil {
            await loadNextTurn()
        }

        if hasFreshCache { return }

        do {
            let result = try await repository.fetchOutline(for: scene, userId: userId)
            if Task.isCancelled { return }
            outline = result.outline
            mergePrefetchedTurns(with: result.turns)
            persistCache()
            if turns.isEmpty, nextStep != nil {
                await loadNextTurn()
            }
        } catch {
            outlineError = mapErrorMessage(error, fallback: "Unable to load the scene outline.")
            if cachedDetail == nil {
                outline = nil
                turns = []
                prefetchedTurns = [:]
                speechAttempts = [:]
                activeSpeechKey = nil
                latestLoadedTurnStep = nil
            }
        }
    }

    var currentPracticeTarget: (key: SpeechKey, line: SpeakLine)? {
        guard let turn = turns.max(by: { $0.step < $1.step }) else { return nil }
        return (SpeechKey(step: turn.step, role: .user), turn.userLine)
    }

    func line(for key: SpeechKey) -> SpeakLine? {
        guard let turn = turns.first(where: { $0.step == key.step }) else { return nil }
        return key.role == .ai ? turn.aiLine : turn.userLine
    }

    func beginSpeech(for key: SpeechKey) {
        activeSpeechKey = key
        speechAttempts[key] = SpeechAttempt(transcript: "", status: .listening, score: nil)
    }

    func updateSpeechTranscript(_ transcript: String, for key: SpeechKey) {
        guard activeSpeechKey == key else { return }
        speechAttempts[key] = SpeechAttempt(transcript: transcript, status: .listening, score: nil)
    }

    func finalizeSpeech(transcript: String, target: String, for key: SpeechKey) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTranscript = trimmed.isEmpty ? (speechAttempts[key]?.transcript ?? "") : transcript
        let normalizedTranscript = normalize(resolvedTranscript)
        let normalizedTarget = normalize(target)
        let score = similarityScore(normalizedTranscript, normalizedTarget)
        let isPerfect = score >= 1.0
        let passed = isPerfect

        speechAttempts[key] = SpeechAttempt(transcript: resolvedTranscript, status: passed ? .passed : .failed, score: score)
        activeSpeechKey = nil

        guard isPerfect else { return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        await loadNextTurn()
    }

    func acceptSpeech(for key: SpeechKey) async {
        var attempt = speechAttempts[key] ?? SpeechAttempt(transcript: "", status: .passed, score: nil)
        attempt.status = .passed
        speechAttempts[key] = attempt
        activeSpeechKey = nil
        await loadNextTurn()
    }

    func cancelSpeech(for key: SpeechKey) {
        if activeSpeechKey == key {
            activeSpeechKey = nil
        }
        speechAttempts.removeValue(forKey: key)
    }

    func loadNextTurn() async {
        guard let outline else { return }
        guard let step = nextStep else { return }
        guard !isLoadingTurn else { return }

        isLoadingTurn = true
        turnError = nil
        let existingSteps = Set(turns.map { $0.step })
        defer { isLoadingTurn = false }

        if let cached = prefetchedTurns[step] {
            prefetchedTurns[step] = nil
            turns = mergeTurns(existing: turns, incoming: cached)
            if !existingSteps.contains(cached.step) {
                latestLoadedTurnStep = cached.step
            }
            persistCache()
            return
        }

        guard let scene = currentScene else { return }
        do {
            let turn = try await repository.fetchTurn(
                scene: scene,
                outline: outline,
                step: step,
                userId: currentUserId
            )
            if Task.isCancelled { return }
            turns = mergeTurns(existing: turns, incoming: turn)
            if !existingSteps.contains(turn.step) {
                latestLoadedTurnStep = turn.step
            }
            persistCache()
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

    private func loadCachedDetail(userId: UUID?, sceneId: UUID) -> SpeakSceneDetailCache? {
        guard let userId else { return nil }
        return LocalSpeakSceneDetailStore.load(userId: userId, sceneId: sceneId)
    }

    private func persistCache() {
        guard let userId = currentUserId, let outline else { return }
        guard currentSceneId == outline.sceneId else { return }
        let cache = SpeakSceneDetailCache(
            outline: outline,
            turns: cachedTurnsSnapshot(),
            cachedAt: Date()
        )
        LocalSpeakSceneDetailStore.save(cache, userId: userId, sceneId: outline.sceneId)
    }

    private func sortTurns(_ list: [SpeakTurn]) -> [SpeakTurn] {
        list.sorted { $0.step < $1.step }
    }

    private func mergeTurns(existing: [SpeakTurn], incoming: SpeakTurn) -> [SpeakTurn] {
        let remaining = existing.filter { $0.step != incoming.step }
        return sortTurns(remaining + [incoming])
    }

    private func mergePrefetchedTurns(with incoming: [SpeakTurn]) {
        let existingSteps = Set(turns.map { $0.step })
        var merged = prefetchedTurns
        for turn in incoming where !existingSteps.contains(turn.step) {
            merged[turn.step] = turn
        }
        prefetchedTurns = merged
    }

    private func cachedTurnsSnapshot() -> [SpeakTurn] {
        let combined = Array(prefetchedTurns.values) + turns
        let byStep = Dictionary(combined.map { ($0.step, $0) }, uniquingKeysWith: { _, new in new })
        return sortTurns(Array(byStep.values))
    }

    private func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let converted = trimmed.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmed
        let filtered = converted.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }
        return String(String.UnicodeScalarView(filtered)).lowercased()
    }

    private func similarityScore(_ first: String, _ second: String) -> Double {
        if first.isEmpty && second.isEmpty { return 1 }
        if first.isEmpty || second.isEmpty { return 0 }
        let distance = levenshtein(Array(first), Array(second))
        let maxLength = max(first.count, second.count)
        return 1 - (Double(distance) / Double(maxLength))
    }

    private func levenshtein(_ first: [Character], _ second: [Character]) -> Int {
        if first.isEmpty { return second.count }
        if second.isEmpty { return first.count }

        var previous = Array(0...second.count)
        var current = Array(repeating: 0, count: second.count + 1)

        for i in 1...first.count {
            current[0] = i
            for j in 1...second.count {
                let cost = first[i - 1] == second[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }

        return previous[second.count]
    }
}

struct SpeechKey: Hashable {
    let step: Int
    let role: SpeakRole
}

enum SpeechAttemptStatus: Equatable {
    case listening
    case passed
    case failed
}

struct SpeechAttempt: Equatable {
    let transcript: String
    var status: SpeechAttemptStatus
    let score: Double?
}
