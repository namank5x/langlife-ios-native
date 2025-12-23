import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechInputService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var partialTranscript = ""
    @Published private(set) var finalTranscript: String?
    @Published private(set) var errorMessage: String?
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

        errorMessage = nil
        transcript = ""
        partialTranscript = ""
        finalTranscript = nil
        lastNonEmptyTranscript = ""

        let status = await requestAuthorization()
        guard status == .authorized else {
            errorMessage = "Enable speech recognition and microphone access in Settings to practice speaking."
            return false
        }

        let hasMicAccess = await requestRecordPermission()
        guard hasMicAccess else {
            errorMessage = "Enable microphone access in Settings to practice speaking."
            return false
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            errorMessage = "Speech recognition is unavailable for this language."
            return false
        }

        guard recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now."
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
                errorMessage = "Could not start the microphone."
                return false
            }
        }

        try? audioSession.setPreferredSampleRate(44_100)
        try? audioSession.setPreferredInputNumberOfChannels(1)

        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not start the microphone."
            return false
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            errorMessage = "Could not start speech recognition."
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
                    self.errorMessage = "We couldn't understand that. Try again."
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
            errorMessage = "Microphone unavailable right now. Try again."
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
            errorMessage = "Could not start recording."
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
        errorMessage = nil
        lastNonEmptyTranscript = ""
    }

    func clearError() {
        errorMessage = nil
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
}
