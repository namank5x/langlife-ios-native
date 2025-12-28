import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechInputService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var partialTranscript = ""
    @Published private(set) var finalTranscript: String?
    @Published private(set) var issue: SpeechInputIssue?
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var lastNonEmptyTranscript = ""

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        authorizationStatus = current
        if current != .notDetermined {
            return current
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func startRecording(localeIdentifier: String = "zh-TW") async -> Bool {
        if isRecording {
            return true
        }

        issue = nil
        transcript = ""
        partialTranscript = ""
        finalTranscript = nil
        lastNonEmptyTranscript = ""

        let status = await requestAuthorization()
        guard status == .authorized else {
            issue = issueForSpeechAuthorization(status)
            return false
        }

        let hasMicAccess = await requestRecordPermission()
        guard hasMicAccess else {
            issue = issueForMicrophonePermission()
            return false
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            issue = .unavailable("Speech recognition is unavailable for this language.")
            return false
        }

        guard recognizer.isAvailable else {
            issue = .unavailable("Speech recognition is unavailable right now.")
            return false
        }

        speechRecognizer = recognizer
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false)
        } catch {
            // If deactivation fails, continue with best effort.
        }

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .allowBluetooth, .defaultToSpeaker]
            )
        } catch {
            do {
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.duckOthers, .defaultToSpeaker]
                )
            } catch {
                issue = .failure("Could not start the microphone.")
                return false
            }
        }

        try? audioSession.setPreferredSampleRate(44_100)
        try? audioSession.setPreferredInputNumberOfChannels(1)

        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            issue = .failure("Could not start the microphone.")
            return false
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            issue = .failure("Could not start speech recognition.")
            return false
        }

        recognitionRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let formatted = result.bestTranscription.formattedString
                    self.partialTranscript = formatted
                    self.transcript = formatted
                    if !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.lastNonEmptyTranscript = formatted
                    }

                    if result.isFinal {
                        let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty, !self.lastNonEmptyTranscript.isEmpty {
                            self.finalTranscript = self.lastNonEmptyTranscript
                        } else {
                            self.finalTranscript = formatted
                        }
                        self.stopRecording()
                    }
                }

                if error != nil {
                    self.issue = .failure("We couldn't understand that. Try again.")
                    self.stopRecording()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        let recordingFormat = inputNode.inputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            issue = .failure("Microphone unavailable right now. Try again.")
            stopRecording()
            return false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            issue = .failure("Could not start recording.")
            stopRecording()
            return false
        }

        isRecording = true
        return true
    }

    private func requestRecordPermission() async -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        switch audioSession.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stopAndFinalize() -> String? {
        let finalCandidate = bestAvailableTranscript()
        stopRecording()
        if finalTranscript == nil, let finalCandidate {
            finalTranscript = finalCandidate
        } else if finalTranscript == nil, finalCandidate == nil {
            finalTranscript = ""
        }
        return finalCandidate
    }

    func reset() {
        stopRecording()
        transcript = ""
        partialTranscript = ""
        finalTranscript = nil
        issue = nil
        lastNonEmptyTranscript = ""
    }

    func clearError() {
        issue = nil
    }

    func refreshAuthorizationState() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        authorizationStatus = speechStatus

        guard issue == nil || issue?.isPermission == true else { return }
        if let speechIssue = issueForSpeechAuthorization(speechStatus) {
            issue = speechIssue
            return
        }

        let micPermission = AVAudioSession.sharedInstance().recordPermission
        if let micIssue = issueForMicrophonePermission(micPermission) {
            issue = micIssue
            return
        }

        issue = nil
    }

    private func bestAvailableTranscript() -> String? {
        if let final = finalTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
           !final.isEmpty {
            return finalTranscript
        }

        let lastTrimmed = lastNonEmptyTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lastTrimmed.isEmpty {
            return lastNonEmptyTranscript
        }

        let partialTrimmed = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partialTrimmed.isEmpty {
            return partialTranscript
        }

        let transcriptTrimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcriptTrimmed.isEmpty {
            return transcript
        }

        return nil
    }

    private func issueForSpeechAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> SpeechInputIssue? {
        switch status {
        case .authorized:
            return nil
        case .denied:
            return .permissionDenied(.speechRecognition)
        case .restricted:
            return .permissionRestricted(.speechRecognition)
        case .notDetermined:
            return nil
        @unknown default:
            return .failure("Speech recognition is unavailable right now.")
        }
    }

    private func issueForMicrophonePermission(
        _ permission: AVAudioSession.RecordPermission? = nil
    ) -> SpeechInputIssue? {
        let resolved = permission ?? AVAudioSession.sharedInstance().recordPermission
        switch resolved {
        case .granted:
            return nil
        case .denied:
            return .permissionDenied(.microphone)
        case .undetermined:
            return nil
        @unknown default:
            return .failure("Microphone access is unavailable right now.")
        }
    }
}

enum SpeechPermissionKind: String, Equatable {
    case speechRecognition = "Speech Recognition"
    case microphone = "Microphone"
}

enum SpeechInputIssue: Equatable {
    case permissionDenied(SpeechPermissionKind)
    case permissionRestricted(SpeechPermissionKind)
    case unavailable(String)
    case failure(String)

    var message: String {
        switch self {
        case .permissionDenied(let kind):
            return "To practice speaking, allow \(kind.rawValue) in Settings."
        case .permissionRestricted(let kind):
            return "\(kind.rawValue) access is restricted on this device."
        case .unavailable(let message),
             .failure(let message):
            return message
        }
    }

    var showsSettingsAction: Bool {
        switch self {
        case .permissionDenied:
            return true
        case .permissionRestricted, .unavailable, .failure:
            return false
        }
    }

    var isPermission: Bool {
        switch self {
        case .permissionDenied, .permissionRestricted:
            return true
        case .unavailable, .failure:
            return false
        }
    }

    var iconName: String {
        switch self {
        case .permissionDenied(.microphone), .permissionRestricted(.microphone):
            return "mic.slash.fill"
        case .permissionDenied(.speechRecognition), .permissionRestricted(.speechRecognition):
            return "waveform.slash"
        case .unavailable:
            return "waveform"
        case .failure:
            return "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .permissionDenied(let kind), .permissionRestricted(let kind):
            return "\(kind.rawValue) needed"
        case .unavailable:
            return "Speech unavailable"
        case .failure:
            return "Speech error"
        }
    }
}
