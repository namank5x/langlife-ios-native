import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class VoiceSessionViewModel: ObservableObject {
    private enum EffectiveTurnDetection {
        case manual
        case serverVAD
        case unknown
    }

    @Published private(set) var state: VoiceSessionState = .idle
    @Published private(set) var transcript: [VoiceTranscriptEntry] = []
    @Published private(set) var currentAgentText = ""
    @Published private(set) var isAgentSpeaking = false
    @Published private(set) var completionResponse: VoiceSessionCompleteResponse?
    @Published private(set) var savedWords: [SavedVocabWord] = []
    @Published private(set) var isPushToSpeakPressed = false

    private let webSocket = GrokWebSocketService()
    private let audioCapture = AudioCaptureService()
    private let audioPlayback = AudioPlaybackService()
    private let repository: VoiceSessionRepository

    private var sessionStartedAt: Date?
    private var messageTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var responseStartWatchdogTask: Task<Void, Never>?
    private var responseCompletionWatchdogTask: Task<Void, Never>?
    private var commitAckWatchdogTask: Task<Void, Never>?
    private var userTurnEvidenceWatchdogTask: Task<Void, Never>?

    private var agentSummary: String?
    private var agentScore: Int?
    private var pendingPrompt: RealtimePromptResponse?
    private var startupAttempt = 0
    private var hasConversationCreated = false
    private var sessionInstructions = ""
    private var sessionTools: [[String: Any]] = []

    private var hasStartedConversation = false
    private var awaitingAssistantResponse = false
    private var didRetryCurrentResponse = false
    private var hasReceivedResponseSignal = false
    private var localAudioChunkCount = 0
    private var localAudioBytesApprox = 0
    private var pressTurnAudioBytes = 0
    private var pendingManualCommit = false
    private var shouldStreamInputAudio = false
    private var shouldDropCurrentAssistantResponse = false
    private var queuedResponseAfterCurrentTurn = false
    private var currentPressTurnID: Int?
    private var pendingCommitTurnID: Int?
    private var pendingUserTurnEvidenceTurnID: Int?
    private var pendingResponseTurnID: Int?
    private var inFlightResponseTurnID: Int?
    private var turnIDSequence = 0
    private var commitRetryCount = 0
    private var lastManualRetryAt = Date.distantPast
    private var effectiveTurnDetection: EffectiveTurnDetection = .unknown

    private static let responseModalities = ["text", "audio"]
    private static let responseStartTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let responseCompletionTimeoutNanoseconds: UInt64 = 25_000_000_000
    private static let startupTimeoutNanoseconds: UInt64 = 10_000_000_000
    private static let startupRetryBackoffNanoseconds: UInt64 = 1_200_000_000
    private static let commitAckTimeoutNanoseconds: UInt64 = 4_000_000_000
    private static let userTurnEvidenceTimeoutNanoseconds: UInt64 = 3_500_000_000
    private static let maxCommitRetries = 1
    private static let maxStartupAttempts = 2
    private static let syntheticKickoffText = "Let's begin the roleplay now. Start in character with your first line in Chinese, then continue naturally."

    init(repository: VoiceSessionRepository = VoiceSessionRepository()) {
        self.repository = repository
    }

    var isPushToSpeakEnabled: Bool {
        guard hasStartedConversation else { return false }
        guard case .conversationActive(let substate) = state else { return false }
        if pendingManualCommit { return false }
        switch substate {
        case .readyToSpeak, .recording, .agentSpeaking:
            return true
        case .processing:
            return false
        }
    }

    func startSession() {
        guard state == .idle else { return }
        resetSessionData()
        resetRuntimeFlags()
        state = .connecting(.openingSocket)
        startStartupAttempt(attempt: 1, isRetry: false)
    }

    func endSession() {
        guard state.isActive else { return }

        startupTask?.cancel()
        startupTask = nil
        cancelStartupWatchdog()
        stopRealtimePipeline()

        let startDate = sessionStartedAt ?? Date()
        let duration = Int(Date().timeIntervalSince(startDate))

        state = .endingSession

        Task {
            do {
                let summary = agentSummary
                    ?? transcript.last(where: { $0.role == .agent })?.text

                let request = VoiceSessionCompleteRequest(
                    startedAt: ISO8601DateFormatter().string(from: startDate),
                    durationSeconds: duration,
                    summary: summary,
                    score: agentScore,
                    wordsPracticed: savedWords
                )
                let response = try await repository.completeSession(request)
                completionResponse = response
                state = .showingResults
            } catch {
                state = .showingResults
            }
        }
    }

    func cleanup() {
        stopPushToSpeakIfNeeded()
        startupTask?.cancel()
        startupTask = nil
        cancelStartupWatchdog()
        stopRealtimePipeline()
        resetRuntimeFlags()
    }

    func beginPushToSpeak() {
        guard hasStartedConversation else { return }
        guard case .conversationActive = state else { return }
        guard isPushToSpeakEnabled else { return }
        guard !isPushToSpeakPressed else { return }
        guard !pendingManualCommit else { return }
        if awaitingAssistantResponse && !isAgentSpeaking {
            return
        }

        if isAgentSpeaking {
            logEvent("ptt.start interrupting assistant")
            shouldDropCurrentAssistantResponse = true
            audioPlayback.stop()
            isAgentSpeaking = false
            currentAgentText = ""
        }

        turnIDSequence += 1
        currentPressTurnID = turnIDSequence
        pressTurnAudioBytes = 0
        isPushToSpeakPressed = true
        shouldStreamInputAudio = true
        logEvent("ptt.start turn=\(currentPressTurnID ?? -1)")
        state = .conversationActive(.recording)
    }

    func endPushToSpeak() {
        guard isPushToSpeakPressed else { return }

        isPushToSpeakPressed = false
        shouldStreamInputAudio = false

        if pressTurnAudioBytes <= 0 {
            logEvent("ptt.end no audio captured turn=\(currentPressTurnID ?? -1)")
            pressTurnAudioBytes = 0
            currentPressTurnID = nil
            setReadyToSpeakState()
            return
        }

        let turnID = currentPressTurnID
        pendingCommitTurnID = turnID
        pendingUserTurnEvidenceTurnID = turnID
        currentPressTurnID = nil

        pendingManualCommit = true
        commitRetryCount = 0
        state = .conversationActive(.processing)
        logEvent("ptt.end commit bytes=\(pressTurnAudioBytes) turn=\(turnID ?? -1)")
        pressTurnAudioBytes = 0
        armUserTurnEvidenceWatchdog(turnID: turnID, trigger: "ptt.end")

        switch effectiveTurnDetection {
        case .manual, .unknown:
            sendCommit(turnID: turnID, reason: "ptt.end")
            armCommitAckWatchdog(turnID: turnID)
        case .serverVAD:
            pendingManualCommit = false
            pendingCommitTurnID = nil
            commitRetryCount = 0
            logEvent("ptt.end turn_detection=server_vad waiting for server turn evidence turn=\(turnID ?? -1)")
        }
    }

    func retryProcessingTurn() {
        guard case .conversationActive(.processing) = state else { return }
        guard !isPushToSpeakPressed else { return }
        guard !pendingManualCommit else { return }

        let now = Date()
        guard now.timeIntervalSince(lastManualRetryAt) >= 1 else { return }
        lastManualRetryAt = now

        let turnID = pendingResponseTurnID ?? inFlightResponseTurnID
        if awaitingAssistantResponse && !hasReceivedResponseSignal {
            logEvent("manual retry response.create turn=\(turnID ?? -1)")
            webSocket.send(.responseCreate(modalities: Self.responseModalities))
            armResponseStartWatchdog(trigger: "manual.retry", turnID: turnID)
            return
        }

        if !awaitingAssistantResponse {
            if pendingResponseTurnID == nil {
                pendingResponseTurnID = turnID
            }
            requestAssistantResponse(trigger: "manual.retry", force: true)
        }
    }

    // MARK: - Startup

    private func startStartupAttempt(attempt: Int, isRetry: Bool) {
        startupAttempt = attempt
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.runStartupAttempt(attempt: attempt, isRetry: isRetry)
        }
    }

    private func runStartupAttempt(attempt: Int, isRetry: Bool) async {
        stopRealtimePipeline()
        resetConversationRuntimeFlags()
        pendingPrompt = nil
        hasConversationCreated = false

        if isRetry {
            state = .connecting(.retrying(attempt: attempt))
            logEvent("startup retry attempt=\(attempt)")
            try? await Task.sleep(nanoseconds: Self.startupRetryBackoffNanoseconds)
            guard !Task.isCancelled else { return }
        }

        state = .connecting(.openingSocket)

        do {
            async let tokenResult = repository.fetchToken()
            async let promptResult = repository.fetchPrompt()

            let token = try await tokenResult
            let prompt = try await promptResult
            guard !Task.isCancelled else { return }

            let permitted = await audioCapture.requestPermission()
            guard permitted else {
                state = .error(message: "Microphone access is required. Please enable it in Settings.")
                cleanup()
                return
            }

            try audioCapture.configureAudioSession()
            pendingPrompt = prompt
            sessionInstructions = prompt.instructions
            sessionTools = prompt.tools

            let messages = webSocket.messages
            messageTask = Task { [weak self] in
                for await message in messages {
                    await self?.handleServerMessage(message)
                }
            }

            logEvent("connecting websocket attempt=\(attempt)")
            webSocket.connect(token: token.clientSecret)
            armStartupWatchdog(stage: .openingSocket, attempt: attempt)

        } catch {
            let message = startupErrorMessage(from: error)
            let recoverable = isRecoverableStartupError(error)
            handleStartupFailure(reason: message, recoverable: recoverable)
        }
    }

    private func startAudioPipeline() throws {
        audioCapture.onChunk = { [weak self] base64 in
            Task { @MainActor [weak self] in
                self?.handleCapturedAudioChunk(base64)
            }
        }
        audioCapture.onChunkStats = nil

        let session = AVAudioSession.sharedInstance()
        let inputRoutes = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        let outputRoutes = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        logEvent("audio route inputs=[\(inputRoutes)] outputs=[\(outputRoutes)]")

        try audioPlayback.start()
        try audioCapture.startCapture()
        logEvent("audio pipeline started capture_running=\(audioCapture.isCapturing)")
    }

    private func handleCapturedAudioChunk(_ base64: String) {
        guard shouldStreamInputAudio else { return }

        let decodedBytes = Self.approximateDecodedByteCount(base64: base64)
        localAudioChunkCount += 1
        localAudioBytesApprox += decodedBytes
        pressTurnAudioBytes += decodedBytes
        if localAudioChunkCount == 1 || localAudioChunkCount % 25 == 0 {
            logEvent(
                "local audio chunks=\(localAudioChunkCount) approx_bytes=\(localAudioBytesApprox) capture_running=\(audioCapture.isCapturing) turn=\(currentPressTurnID ?? -1)"
            )
        }
        webSocket.send(.inputAudioBufferAppend(audio: base64))
    }

    private func handleStartupFailure(reason: String, recoverable: Bool) {
        cancelStartupWatchdog()
        stopRealtimePipeline()

        if recoverable && startupAttempt < Self.maxStartupAttempts {
            let nextAttempt = startupAttempt + 1
            logEvent("startup failure attempt=\(startupAttempt) reason=\(reason) retrying=\(nextAttempt)")
            startStartupAttempt(attempt: nextAttempt, isRetry: true)
            return
        }

        logEvent("startup failed attempt=\(startupAttempt) reason=\(reason)")
        state = .error(message: "Couldn't connect to voice service. Check your network and try again.")
        cleanup()
    }

    private func armStartupWatchdog(stage: VoiceSessionState.ConnectionStage, attempt: Int) {
        cancelStartupWatchdog()
        startupWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.startupTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleStartupTimeout(stage: stage, attempt: attempt)
        }
    }

    private func handleStartupTimeout(stage: VoiceSessionState.ConnectionStage, attempt: Int) {
        guard startupAttempt == attempt else { return }
        guard case .connecting(let currentStage) = state else { return }
        guard currentStage == stage else { return }

        logEvent("startup timeout stage=\(String(describing: stage)) attempt=\(attempt)")
        handleStartupFailure(reason: "Timed out while \(stage.statusText)", recoverable: true)
    }

    private func cancelStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
    }

    private var isStartupInProgress: Bool {
        if case .connecting = state {
            return true
        }
        return false
    }

    // MARK: - Message Handling

    private func handleServerMessage(_ message: GrokServerMessage) {
        switch message {
        case .transportConnected:
            logEvent("transport.connected")
            guard isStartupInProgress else { return }
            guard pendingPrompt != nil else {
                handleStartupFailure(reason: "Missing session configuration", recoverable: true)
                return
            }

            cancelStartupWatchdog()
            state = .connecting(.configuringSession)
            sendSessionUpdate(turnDetection: .none, trigger: "startup")
            armStartupWatchdog(stage: .configuringSession, attempt: startupAttempt)
            if hasConversationCreated {
                completeStartup(trigger: "conversation.created.cached")
            }

        case .transportDisconnected(let reason):
            logEvent("transport.disconnected reason=\(reason)")
            if isStartupInProgress {
                handleStartupFailure(reason: reason, recoverable: true)
            } else if state.isActive {
                state = .error(message: "Voice connection lost. Please try again.")
                cleanup()
            }

        case .sessionCreated(let turnDetectionType):
            applyEffectiveTurnDetection(turnDetectionType, source: "session.created")

        case .conversationCreated:
            logEvent("conversation.created")
            hasConversationCreated = true
            if isStartupInProgress {
                completeStartup(trigger: "conversation.created")
            }

        case .ping(let eventID):
            logEvent("ping")
            webSocket.send(.pong(eventID: eventID))

        case .sessionUpdated(let turnDetectionType, let inputRate, let outputRate):
            applyEffectiveTurnDetection(turnDetectionType, source: "session.updated")
            let inputRateText = inputRate.map(String.init) ?? "nil"
            let outputRateText = outputRate.map(String.init) ?? "nil"
            logEvent("session.updated audio.input.rate=\(inputRateText) audio.output.rate=\(outputRateText)")
            completeStartup(trigger: "session.updated")

        case .inputAudioBufferSpeechStarted:
            logEvent("input_audio_buffer.speech_started")

        case .inputAudioBufferSpeechStopped:
            logEvent("input_audio_buffer.speech_stopped")
            resolvePendingUserTurnEvidence(trigger: "input_audio_buffer.speech_stopped")

        case .inputAudioBufferCommitted:
            logEvent("input_audio_buffer.committed turn=\(pendingCommitTurnID ?? -1)")
            pendingManualCommit = false
            cancelCommitAckWatchdog()
            commitRetryCount = 0
            resolvePendingUserTurnEvidence(trigger: "input_audio_buffer.committed")

        case .inputAudioBufferCleared:
            logEvent("input_audio_buffer.cleared")

        case .conversationItemAdded(let role, let transcriptText):
            if role == "user" {
                resolvePendingUserTurnEvidence(trigger: "conversation.item.added.user")
            }
            if let role, let transcriptText {
                let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && role == "user" {
                    appendTranscriptIfNeeded(role: .user, text: trimmed)
                }
            }

        case .inputAudioTranscriptionCompleted(let text):
            if !text.isEmpty {
                logEvent("conversation.item.input_audio_transcription.completed chars=\(text.count)")
                appendTranscriptIfNeeded(role: .user, text: text)
                resolvePendingUserTurnEvidence(trigger: "conversation.item.input_audio_transcription.completed")
            }

        case .responseCreated:
            guard awaitingAssistantResponse else {
                logEvent("response.created ignored no in-flight response")
                break
            }
            logEvent("response.created turn=\(inFlightResponseTurnID ?? -1)")
            markResponseStarted(signal: "response.created")

        case .responseAudioDelta(let delta):
            guard awaitingAssistantResponse else {
                logEvent("response.output_audio.delta ignored no in-flight response")
                break
            }
            if shouldDropCurrentAssistantResponse {
                break
            }
            markResponseStarted(signal: "response.output_audio.delta")
            isAgentSpeaking = true
            if case .conversationActive = state {
                state = .conversationActive(.agentSpeaking)
            }
            audioPlayback.enqueueAudio(base64: delta)

        case .responseAudioDone:
            guard awaitingAssistantResponse else {
                logEvent("response.output_audio.done ignored no in-flight response")
                break
            }
            logEvent("response.output_audio.done")

        case .responseAudioTranscriptDelta(let delta):
            guard awaitingAssistantResponse else {
                logEvent("response.output_audio_transcript.delta ignored no in-flight response")
                break
            }
            if shouldDropCurrentAssistantResponse {
                break
            }
            markResponseStarted(signal: "response.output_audio_transcript.delta")
            currentAgentText += delta

        case .responseAudioTranscriptDone(let fullTranscript):
            guard awaitingAssistantResponse else {
                logEvent("response.output_audio_transcript.done ignored no in-flight response")
                currentAgentText = ""
                break
            }
            if shouldDropCurrentAssistantResponse {
                currentAgentText = ""
                break
            }
            let text = fullTranscript.isEmpty ? currentAgentText : fullTranscript
            if !text.isEmpty {
                logEvent("response.output_audio_transcript.done chars=\(text.count)")
                appendTranscriptIfNeeded(role: .agent, text: text)
            }
            currentAgentText = ""

        case .responseOutputItemAdded:
            break

        case .responseOutputItemDone:
            break

        case .responseContentPartAdded:
            break

        case .responseContentPartDone:
            break

        case .responseFunctionCallArgumentsDone(let callId, let name, let arguments):
            logEvent("response.function_call_arguments.done name=\(name)")
            handleFunctionCall(callId: callId, name: name, arguments: arguments)

        case .responseDone:
            guard awaitingAssistantResponse else {
                logEvent("response.done ignored no in-flight response")
                break
            }
            logEvent("response.done turn=\(inFlightResponseTurnID ?? -1)")
            logEvent("audio diagnostics local_chunks=\(localAudioChunkCount) approx_bytes=\(localAudioBytesApprox)")
            cancelResponseStartWatchdog()
            cancelResponseCompletionWatchdog()
            awaitingAssistantResponse = false
            didRetryCurrentResponse = false
            hasReceivedResponseSignal = false
            isAgentSpeaking = false
            inFlightResponseTurnID = nil
            if shouldDropCurrentAssistantResponse {
                shouldDropCurrentAssistantResponse = false
            }
            if queuedResponseAfterCurrentTurn {
                queuedResponseAfterCurrentTurn = false
                requestAssistantResponse(trigger: "queued.after_response_done", force: true)
            } else if case .conversationActive = state,
                      !isPushToSpeakPressed,
                      !pendingManualCommit {
                setReadyToSpeakState()
            }

        case .error(let errorMessage):
            logEvent("error \(errorMessage)")
            if isStartupInProgress {
                handleStartupFailure(reason: errorMessage, recoverable: true)
            } else {
                state = .error(message: errorMessage)
                cleanup()
            }

        case .unknown(let type):
            logEvent("unknown event type=\(type)")
        }
    }

    // MARK: - Turn Control

    private func sendSessionUpdate(turnDetection: GrokClientMessage.TurnDetection, trigger: String) {
        guard !sessionInstructions.isEmpty else { return }
        let modeLabel: String
        switch turnDetection {
        case .serverVAD:
            modeLabel = "server_vad"
        case .none:
            modeLabel = "none"
        }
        logEvent("client session.update trigger=\(trigger) turn_detection=\(modeLabel)")
        webSocket.send(
            .sessionUpdate(
                instructions: sessionInstructions,
                tools: sessionTools,
                turnDetection: turnDetection
            )
        )
    }

    private func setReadyToSpeakState() {
        state = .conversationActive(.readyToSpeak)
    }

    private func appendTranscriptIfNeeded(role: VoiceTranscriptEntry.Role, text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if let last = transcript.last, last.role == role, last.text == normalized {
            return
        }
        transcript.append(VoiceTranscriptEntry(role: role, text: normalized))
    }

    private func handleCommittedUserTurn(trigger: String, turnID: Int?) {
        if let turnID {
            pendingResponseTurnID = turnID
        }
        if awaitingAssistantResponse {
            queuedResponseAfterCurrentTurn = true
            state = .conversationActive(.processing)
            logEvent("queued response after current assistant turn trigger=\(trigger) turn=\(turnID ?? -1)")
            return
        }
        requestAssistantResponse(trigger: trigger)
    }

    private func stopPushToSpeakIfNeeded() {
        guard isPushToSpeakPressed || shouldStreamInputAudio || pendingManualCommit || pendingUserTurnEvidenceTurnID != nil else { return }
        logEvent("ptt.cancel")
        isPushToSpeakPressed = false
        shouldStreamInputAudio = false
        pressTurnAudioBytes = 0
        currentPressTurnID = nil
        pendingCommitTurnID = nil
        pendingUserTurnEvidenceTurnID = nil
        pendingManualCommit = false
        commitRetryCount = 0
        cancelCommitAckWatchdog()
        cancelUserTurnEvidenceWatchdog()
        if case .conversationActive = state {
            setReadyToSpeakState()
        }
    }

    // MARK: - Function Call Handling

    private func handleFunctionCall(callId: String, name: String, arguments: String) {
        let parsedArgs = parseArguments(arguments)

        let output: String
        switch name {
        case "end_scene":
            agentSummary = parsedArgs["summary"] as? String
            agentScore = parsedArgs["score"] as? Int
            output = "{\"status\": \"ending\"}"
            webSocket.send(.conversationItemCreate(callId: callId, output: output))
            requestAssistantResponse(trigger: "function.end_scene", force: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                endSession()
            }
            return

        case "save_vocabulary":
            if let wordsArray = parsedArgs["words"] as? [[String: Any]] {
                let newWords = wordsArray.compactMap { dict -> SavedVocabWord? in
                    guard let chinese = dict["chinese"] as? String,
                          let pinyin = dict["pinyin"] as? String,
                          let english = dict["english"] as? String else {
                        return nil
                    }
                    return SavedVocabWord(
                        chinese: chinese,
                        pinyin: pinyin,
                        english: english,
                        example: dict["example"] as? String,
                        examplePinyin: dict["examplePinyin"] as? String,
                        exampleEnglish: dict["exampleEnglish"] as? String
                    )
                }
                savedWords.append(contentsOf: newWords)
                output = "{\"status\": \"saved\", \"count\": \(newWords.count)}"
            } else {
                output = "{\"status\": \"error\", \"message\": \"no words provided\"}"
            }

        default:
            output = "{\"status\": \"ok\"}"
        }

        webSocket.send(.conversationItemCreate(callId: callId, output: output))
        requestAssistantResponse(trigger: "function.\(name)", force: true)
    }

    private func parseArguments(_ arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    // MARK: - Response Flow

    private func requestAssistantResponse(trigger: String, force: Bool = false) {
        guard case .conversationActive = state else { return }
        if pendingManualCommit && !force {
            return
        }
        if awaitingAssistantResponse && !force {
            return
        }

        let turnID = pendingResponseTurnID ?? inFlightResponseTurnID
        if inFlightResponseTurnID == nil {
            inFlightResponseTurnID = turnID
        }
        pendingResponseTurnID = nil

        awaitingAssistantResponse = true
        didRetryCurrentResponse = false
        hasReceivedResponseSignal = false
        shouldDropCurrentAssistantResponse = false
        state = .conversationActive(.processing)

        logEvent("client response.create trigger=\(trigger) turn=\(turnID ?? -1)")
        webSocket.send(.responseCreate(modalities: Self.responseModalities))
        armResponseStartWatchdog(trigger: trigger, turnID: turnID)
    }

    private func sendCommit(turnID: Int?, reason: String) {
        logEvent("client input_audio_buffer.commit reason=\(reason) attempt=\(commitRetryCount + 1) turn=\(turnID ?? -1)")
        webSocket.send(.inputAudioBufferCommit)
    }

    private func applyEffectiveTurnDetection(_ serverType: String?, source: String) {
        let normalized = serverType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mode: EffectiveTurnDetection
        if normalized == nil || normalized == "null" || normalized == "none" {
            mode = .manual
        } else if normalized == "server_vad" {
            mode = .serverVAD
        } else {
            mode = .unknown
        }
        effectiveTurnDetection = mode
        let label: String
        switch mode {
        case .manual:
            label = "manual(null)"
        case .serverVAD:
            label = "server_vad"
        case .unknown:
            label = normalized ?? "unknown"
        }
        logEvent("session turn_detection effective=\(label) source=\(source)")
    }

    private func resolvePendingUserTurnEvidence(trigger: String) {
        guard let turnID = pendingUserTurnEvidenceTurnID else { return }

        pendingUserTurnEvidenceTurnID = nil
        pendingCommitTurnID = nil
        pendingManualCommit = false
        commitRetryCount = 0
        cancelCommitAckWatchdog()
        cancelUserTurnEvidenceWatchdog()
        handleCommittedUserTurn(trigger: trigger, turnID: turnID)
    }

    private func markResponseStarted(signal: String) {
        if !hasReceivedResponseSignal {
            logEvent("response started signal=\(signal) turn=\(inFlightResponseTurnID ?? -1)")
            armResponseCompletionWatchdog(turnID: inFlightResponseTurnID)
        }
        hasReceivedResponseSignal = true
        cancelResponseStartWatchdog()
    }

    private func armResponseStartWatchdog(trigger: String, turnID: Int?) {
        cancelResponseStartWatchdog()
        responseStartWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.responseStartTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleResponseStartTimeout(trigger: trigger, turnID: turnID)
        }
    }

    private func handleResponseStartTimeout(trigger: String, turnID: Int?) {
        guard awaitingAssistantResponse else { return }
        guard !hasReceivedResponseSignal else { return }
        if !didRetryCurrentResponse {
            didRetryCurrentResponse = true
            logEvent("response start timeout, retrying trigger=\(trigger) turn=\(turnID ?? -1)")
            webSocket.send(.responseCreate(modalities: Self.responseModalities))
            armResponseStartWatchdog(trigger: "\(trigger).retry", turnID: turnID)
            return
        }

        logEvent("response start timeout after retry trigger=\(trigger) turn=\(turnID ?? -1)")
        awaitingAssistantResponse = false
        didRetryCurrentResponse = false
        hasReceivedResponseSignal = false
        isAgentSpeaking = false
        inFlightResponseTurnID = nil
        if queuedResponseAfterCurrentTurn {
            queuedResponseAfterCurrentTurn = false
            requestAssistantResponse(trigger: "queued.after_response_start_timeout", force: true)
        } else if case .conversationActive = state, !isPushToSpeakPressed, !pendingManualCommit {
            setReadyToSpeakState()
        }
    }

    private func cancelResponseStartWatchdog() {
        responseStartWatchdogTask?.cancel()
        responseStartWatchdogTask = nil
    }

    private func armResponseCompletionWatchdog(turnID: Int?) {
        cancelResponseCompletionWatchdog()
        responseCompletionWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.responseCompletionTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleResponseCompletionTimeout(turnID: turnID)
        }
    }

    private func handleResponseCompletionTimeout(turnID: Int?) {
        guard awaitingAssistantResponse else { return }
        guard hasReceivedResponseSignal else { return }

        logEvent("response completion timeout turn=\(turnID ?? -1)")
        cancelResponseCompletionWatchdog()
        awaitingAssistantResponse = false
        didRetryCurrentResponse = false
        hasReceivedResponseSignal = false
        isAgentSpeaking = false
        shouldDropCurrentAssistantResponse = false
        audioPlayback.stop()
        inFlightResponseTurnID = nil

        if queuedResponseAfterCurrentTurn {
            queuedResponseAfterCurrentTurn = false
            requestAssistantResponse(trigger: "queued.after_response_completion_timeout", force: true)
        } else if case .conversationActive = state, !isPushToSpeakPressed, !pendingManualCommit {
            setReadyToSpeakState()
        }
    }

    private func cancelResponseCompletionWatchdog() {
        responseCompletionWatchdogTask?.cancel()
        responseCompletionWatchdogTask = nil
    }

    private func armCommitAckWatchdog(turnID: Int?) {
        cancelCommitAckWatchdog()
        commitAckWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.commitAckTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleCommitAckTimeout(turnID: turnID)
        }
    }

    private func handleCommitAckTimeout(turnID: Int?) {
        guard pendingManualCommit else { return }
        guard pendingCommitTurnID == turnID else { return }

        if commitRetryCount < Self.maxCommitRetries {
            commitRetryCount += 1
            logEvent("manual commit ack timeout, retrying turn=\(turnID ?? -1)")
            sendCommit(turnID: turnID, reason: "commit.ack.timeout.retry")
            armCommitAckWatchdog(turnID: turnID)
            return
        }

        pendingManualCommit = false
        pendingCommitTurnID = nil
        commitRetryCount = 0
        logEvent("manual commit ack timeout after retry, assuming committed turn=\(turnID ?? -1)")
        if pendingUserTurnEvidenceTurnID == nil {
            pendingUserTurnEvidenceTurnID = turnID
        }
        resolvePendingUserTurnEvidence(trigger: "manual.commit.timeout.assume")
    }

    private func cancelCommitAckWatchdog() {
        commitAckWatchdogTask?.cancel()
        commitAckWatchdogTask = nil
    }

    private func armUserTurnEvidenceWatchdog(turnID: Int?, trigger: String) {
        cancelUserTurnEvidenceWatchdog()
        userTurnEvidenceWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.userTurnEvidenceTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleUserTurnEvidenceTimeout(turnID: turnID, trigger: trigger)
        }
    }

    private func handleUserTurnEvidenceTimeout(turnID: Int?, trigger: String) {
        guard let pendingTurnID = pendingUserTurnEvidenceTurnID else { return }
        guard pendingTurnID == turnID else { return }

        pendingUserTurnEvidenceTurnID = nil
        pendingManualCommit = false
        pendingCommitTurnID = nil
        commitRetryCount = 0
        cancelCommitAckWatchdog()
        logEvent("user turn evidence timeout trigger=\(trigger) turn=\(turnID ?? -1), forcing response.create")
        handleCommittedUserTurn(trigger: "user.turn.evidence.timeout", turnID: turnID)
    }

    private func cancelUserTurnEvidenceWatchdog() {
        userTurnEvidenceWatchdogTask?.cancel()
        userTurnEvidenceWatchdogTask = nil
    }

    // MARK: - Helpers

    private func stopRealtimePipeline() {
        stopPushToSpeakIfNeeded()
        cancelResponseStartWatchdog()
        cancelResponseCompletionWatchdog()
        cancelCommitAckWatchdog()
        cancelUserTurnEvidenceWatchdog()
        messageTask?.cancel()
        messageTask = nil
        audioCapture.stopCapture()
        audioCapture.onChunk = nil
        audioCapture.onChunkStats = nil
        audioPlayback.stop()
        webSocket.disconnect()
    }

    private func resetSessionData() {
        transcript = []
        currentAgentText = ""
        isAgentSpeaking = false
        completionResponse = nil
        savedWords = []
        sessionStartedAt = nil
        agentSummary = nil
        agentScore = nil
    }

    private func resetRuntimeFlags() {
        cancelResponseStartWatchdog()
        cancelResponseCompletionWatchdog()
        cancelStartupWatchdog()
        cancelCommitAckWatchdog()
        cancelUserTurnEvidenceWatchdog()
        pendingPrompt = nil
        startupAttempt = 0
        hasConversationCreated = false
        sessionInstructions = ""
        sessionTools = []
        isPushToSpeakPressed = false
        resetConversationRuntimeFlags()
    }

    private func resetConversationRuntimeFlags() {
        hasStartedConversation = false
        awaitingAssistantResponse = false
        didRetryCurrentResponse = false
        hasReceivedResponseSignal = false
        localAudioChunkCount = 0
        localAudioBytesApprox = 0
        pressTurnAudioBytes = 0
        shouldStreamInputAudio = false
        shouldDropCurrentAssistantResponse = false
        queuedResponseAfterCurrentTurn = false
        pendingManualCommit = false
        currentPressTurnID = nil
        pendingCommitTurnID = nil
        pendingUserTurnEvidenceTurnID = nil
        pendingResponseTurnID = nil
        inFlightResponseTurnID = nil
        turnIDSequence = 0
        commitRetryCount = 0
        lastManualRetryAt = Date.distantPast
        effectiveTurnDetection = .unknown
    }

    private func startupErrorMessage(from error: Error) -> String {
        switch error {
        case let apiError as APIClientError:
            return apiError.localizedDescription
        case let urlError as URLError:
            return "Unable to reach server: \(urlError.localizedDescription)"
        case is DecodingError, is RealtimeConfigError:
            return "Unexpected server response. Please update the app."
        default:
            return "Failed to start session: \(error.localizedDescription)"
        }
    }

    private func isRecoverableStartupError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }

        if let apiError = error as? APIClientError,
           case .httpError(let statusCode) = apiError {
            return statusCode >= 500
        }

        return false
    }

    private func logEvent(_ message: String) {
        print("[VoiceSession] \(Date().ISO8601Format()) \(message)")
    }

    private static func approximateDecodedByteCount(base64: String) -> Int {
        let length = base64.count
        guard length > 0 else { return 0 }
        var padding = 0
        if base64.hasSuffix("==") {
            padding = 2
        } else if base64.hasSuffix("=") {
            padding = 1
        }
        return (length * 3) / 4 - padding
    }

    private func completeStartup(trigger: String) {
        guard isStartupInProgress else { return }
        guard !hasStartedConversation else { return }
        guard case .connecting(let stage) = state else { return }
        guard stage == .configuringSession || stage == .startingAudio else { return }

        cancelStartupWatchdog()
        state = .connecting(.startingAudio)

        do {
            try startAudioPipeline()
            setReadyToSpeakState()
            sessionStartedAt = Date()
            hasStartedConversation = true
            startupTask = nil
            logEvent("session ready via \(trigger), entering push_to_speak ready state")
            webSocket.send(.conversationUserMessageCreate(text: Self.syntheticKickoffText))
            requestAssistantResponse(trigger: "session.synthetic_kickoff")
        } catch {
            handleStartupFailure(reason: "Audio startup failed: \(error.localizedDescription)", recoverable: true)
        }
    }
}
