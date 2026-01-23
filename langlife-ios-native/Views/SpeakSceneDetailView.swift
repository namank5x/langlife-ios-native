import Auth
import SwiftUI
import Translation
import _Translation_SwiftUI
import UIKit
import CoreHaptics

struct SpeakSceneDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = SpeakSceneDetailViewModel()
    @StateObject private var ttsService = TTSService()
    @StateObject private var speechService = SpeechInputService()
    @State private var revealedTranslations: Set<TranslationKey> = []
    @State private var transcriptTranslations: [SpeechKey: TranscriptTranslation] = [:]
    @State private var transcriptTranslationQueue = TranscriptTranslationQueue()
    @State private var isOutlinePresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeletingScene = false
    @State private var deleteError: String?
    @State private var lastAutoPlayedStep: Int?
    @State private var activeGlossSelection: GlossSelection?
    @State private var suppressGlossDismiss = false
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentMetrics: ScrollContentMetrics = .zero
    @State private var isNearBottom = true
    @State private var isMicPulseExpanded = false
    @State private var isStartingMic = false
    private let startHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let stopHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let cancelHapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let errorHapticGenerator = UINotificationFeedbackGenerator()
    private let scrollBottomSpacerHeight: CGFloat = 140
    private let micButtonSize = CGSize(width: 132, height: 64)
    private let micCornerRadius: CGFloat = 22
    private let deletionRepository = SpeakSceneDeletionRepository()
    let scene: SpeakScene
    let onDelete: (SpeakScene) -> Void

    var body: some View {
        sceneChrome
    }

    private var sceneChrome: some View {
        sceneLifecycle
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(scene.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label("Delete scene", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Scene actions")
                    .disabled(isDeletingScene)
                }
            }
            .confirmationDialog(
                "Delete this scene?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete scene", role: .destructive) {
                    Task {
                        await deleteScene()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $isOutlinePresented) {
                NavigationStack {
                    outlineContent
                        .navigationTitle("Outline")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    isOutlinePresented = false
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    private var sceneLifecycle: some View {
        sceneContent
            .task(id: scene.id) {
                speechService.reset()
                lastAutoPlayedStep = nil
                transcriptTranslations = [:]
                transcriptTranslationQueue = TranscriptTranslationQueue()
                await viewModel.loadOutline(scene: scene, userId: authManager.user?.id)
            }
            .onDisappear {
                transcriptTranslationQueue.finish()
            }
            .onChange(of: speechService.partialTranscript) { _, transcript in
                guard speechService.isRecording, let key = viewModel.activeSpeechKey else { return }
                viewModel.updateSpeechTranscript(transcript, for: key)
            }
            .onChange(of: speechService.finalTranscript) { _, transcript in
                guard let transcript, let key = viewModel.activeSpeechKey else { return }
                guard let line = viewModel.line(for: key) else { return }
                viewModel.updateSpeechStatus(.processing, for: key)
                Task {
                    await viewModel.finalizeSpeech(transcript: transcript, target: line.chinese, for: key)
                    if let resolvedTranscript = viewModel.speechAttempts[key]?.transcript {
                        await MainActor.run {
                            queueTranscriptTranslation(for: key, transcript: resolvedTranscript)
                        }
                    }
                }
            }
            .onChange(of: speechService.issue) { _, issue in
                if issue != nil {
                    performHaptic(.error)
                }
                guard issue != nil, let key = viewModel.activeSpeechKey else { return }
                viewModel.failSpeech(for: key, message: issue?.message ?? "Speech unavailable right now.")
            }
            .onChange(of: viewModel.latestLoadedTurnStep) { _, step in
                guard let step else { return }
                guard step != lastAutoPlayedStep else { return }
                guard !speechService.isRecording else { return }
                guard let turn = viewModel.turns.first(where: { $0.step == step }) else { return }
                let trimmed = turn.aiLine.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                lastAutoPlayedStep = step
                Task {
                    ttsService.stop()
                    await ttsService.play(text: trimmed)
                }
            }
            .onAppear {
                prepareAllHaptics()
                updateMicPulseState()
            }
            .onChange(of: speechService.isRecording) { _, _ in
                if !speechService.isRecording {
                    if let key = viewModel.activeSpeechKey {
                        viewModel.updateSpeechStatus(.processing, for: key)
                    }
                }
                updateMicPulseState()
            }
            .onChange(of: isStartingMic) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: viewModel.activeSpeechKey) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: viewModel.turns) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: viewModel.isLoadingTurn) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: ttsService.isPlaying) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: ttsService.isLoading) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: reduceMotion) { _, _ in
                updateMicPulseState()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    speechService.cancelRecording()
                    if let key = viewModel.activeSpeechKey {
                        viewModel.cancelSpeech(for: key)
                    }
                    return
                }
                prepareAllHaptics()
                speechService.refreshAuthorizationState()
            }
            .translationTask(
                source: Locale.Language(identifier: "zh-Hant"),
                target: Locale.Language(identifier: "en")
            ) { session in
                await runTranscriptTranslationLoop(using: session)
            }
    }

    private var outlineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoadingOutline && viewModel.outline == nil {
                    centeredLoadingBlock(
                        label: "Loading outline",
                        phrases: [
                            "Preparing the scene...",
                            "Building the outline...",
                            "Setting up your practice..."
                        ]
                    )
                } else if let outline = viewModel.outline {
                    OutlinePanel(outline: outline)
                } else if let error = viewModel.outlineError {
                        ErrorCard(message: error) {
                            Task {
                                await viewModel.loadOutline(scene: scene, userId: authManager.user?.id)
                            }
                        }
                    } else {
                    Text("Preparing the scene...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(16)
        }
    }

    private func centeredLoadingBlock(label: String, phrases: [String]) -> some View {
        VStack {
            Spacer(minLength: 0)
            RotatingLoadingText(phrases: phrases)
                .accessibilityLabel(label)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var sceneContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let deleteError {
                        ErrorCard(message: deleteError, actionTitle: "Dismiss") {
                            self.deleteError = nil
                        }
                    }
                    if viewModel.isLoadingOutline && viewModel.outline == nil {
                        centeredLoadingBlock(
                            label: "Loading scene",
                            phrases: [
                                "Preparing the scene...",
                                "Building the outline...",
                                "Setting up your practice..."
                            ]
                        )
                    } else if viewModel.outline == nil, let error = viewModel.outlineError {
                        ErrorCard(message: error) {
                            Task {
                                await viewModel.loadOutline(scene: scene, userId: authManager.user?.id)
                            }
                        }
                    } else if viewModel.outline != nil {
                        ConversationPanel(
                            turns: viewModel.turns,
                            isLoadingTurn: viewModel.isLoadingTurn,
                            turnError: viewModel.turnError,
                            speechAttempts: viewModel.speechAttempts,
                            activeSpeechKey: viewModel.activeSpeechKey,
                            activeTranscript: speechService.partialTranscript,
                            speechIssue: speechService.issue,
                            ttsService: ttsService,
                            transcriptTranslations: transcriptTranslations,
                            activeGlossSelection: $activeGlossSelection,
                            revealedTranslations: $revealedTranslations,
                            onGlossInteraction: {
                                suppressNextGlossDismiss()
                            },
                            onRetrySpeech: { key in
                                Task {
                                    await startSpeech(for: key)
                                }
                            },
                            onAcceptSpeech: { key in
                                Task {
                                    await viewModel.acceptSpeech(for: key)
                                }
                            },
                            onDismissSpeechError: {
                                speechService.clearError()
                            },
                            onNext: {
                                Task {
                                    await viewModel.loadNextTurn()
                                }
                            },
                            bottomSpacerHeight: scrollBottomSpacerHeight
                        )

                    }
                }
                .padding(16)
                .background(
                    GeometryReader { contentProxy in
                        Color.clear.preference(
                            key: ScrollContentMetricsKey.self,
                            value: ScrollContentMetrics(
                                height: contentProxy.size.height,
                                minY: contentProxy.frame(in: .named("conversation-scroll")).minY
                            )
                        )
                    }
                )
            }
            .coordinateSpace(name: "conversation-scroll")
            .background(
                GeometryReader { scrollProxy in
                    Color.clear.preference(
                        key: ScrollViewHeightKey.self,
                        value: scrollProxy.size.height
                    )
                }
            )
            .onPreferenceChange(ScrollContentMetricsKey.self) { metrics in
                contentMetrics = metrics
                updateIsNearBottom()
            }
            .onPreferenceChange(ScrollViewHeightKey.self) { height in
                scrollViewHeight = height
                updateIsNearBottom()
            }
            .onChange(of: viewModel.latestLoadedTurnStep) { _, _ in
                guard viewModel.latestLoadedTurnStep != nil else { return }
                guard isNearBottom else { return }
                Task {
                    await Task.yield()
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(ScrollAnchor.bottom, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SpeakSceneBottomBar(
                isOutlinePresented: $isOutlinePresented,
                shouldPulse: shouldPulseMic,
                isPulseExpanded: isMicPulseExpanded,
                reduceMotion: reduceMotion,
                isRecording: speechService.isRecording,
                isStartingMic: isStartingMic,
                accessibilityLabel: micAccessibilityLabel,
                accessibilityHint: micAccessibilityHint,
                micButtonSize: micButtonSize,
                micCornerRadius: micCornerRadius,
                onTap: {
                    handleMicTap()
                }
            )
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                guard activeGlossSelection != nil else { return }
                guard !suppressGlossDismiss else { return }
                activeGlossSelection = nil
            }
        )
    }

    @MainActor
    private func handleMicTap() {
        let isStopping = speechService.isRecording || isStartingMic
        if isStopping {
            prepareHaptic(for: .stop)
            performHaptic(.stop)
        } else {
            prepareHaptic(for: .start)
            performHaptic(.start)
        }
        Task {
            await toggleMic()
        }
    }

    @MainActor
    private func toggleMic() async {
        if speechService.isRecording || isStartingMic {
            stopRecording()
            return
        }
        await startRecording()
    }

    @MainActor
    private func startRecording() async {
        guard !isStartingMic else { return }
        guard !speechService.isRecording else { return }
        guard let target = viewModel.currentPracticeTarget else { return }
        let key = target.key

        viewModel.beginSpeech(for: key)
        isStartingMic = true
        defer { isStartingMic = false }

        if ttsService.isPlaying {
            ttsService.stop()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        resetTranscriptTranslation(for: target.key)
        viewModel.updateSpeechStatus(.connecting, for: key)

        let started = await speechService.startRecording(localeIdentifier: "zh-TW")

        guard viewModel.activeSpeechKey == key else {
            if speechService.isRecording {
                speechService.cancelRecording()
            }
            return
        }

        if started {
            viewModel.updateSpeechStatus(.listening, for: key)
        } else {
            let message = speechService.issue?.message ?? "Could not start the microphone."
            viewModel.failSpeech(for: key, message: message)
            performHaptic(.error)
        }
    }

    @MainActor
    private func stopRecording() {
        if isStartingMic {
            speechService.cancelRecording()
            if let key = viewModel.activeSpeechKey {
                viewModel.cancelSpeech(for: key)
            }
            isStartingMic = false
            performHaptic(.cancel)
            return
        }

        if speechService.isRecording {
            if let key = viewModel.activeSpeechKey {
                viewModel.updateSpeechStatus(.processing, for: key)
            }
            _ = speechService.stopAndFinalize()
            performHaptic(.stop)
        } else if let key = viewModel.activeSpeechKey {
            viewModel.cancelSpeech(for: key)
        }
    }

    @MainActor
    private func deleteScene() async {
        guard !isDeletingScene else { return }
        guard let userId = authManager.user?.id else {
            deleteError = "Please sign in to delete this scene."
            return
        }

        isDeletingScene = true
        deleteError = nil
        defer { isDeletingScene = false }

        do {
            if LocalSceneOutboxStore.pendingSceneIds(userId: userId).contains(scene.id) {
                onDelete(scene)
                dismiss()
                return
            }
            try await deletionRepository.deleteScene(id: scene.id)
            onDelete(scene)
            dismiss()
        } catch {
            if isMissingRemoteScene(error) {
                onDelete(scene)
                dismiss()
                return
            }
            deleteError = mapDeleteSceneError(error)
        }
    }

    private func mapDeleteSceneError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return "Unable to delete this scene right now."
        }

        switch apiError {
        case .httpError(let statusCode):
            switch statusCode {
            case 401:
                return "Please sign in to delete this scene."
            default:
                return "Unable to delete this scene right now."
            }
        }
    }

    private func isMissingRemoteScene(_ error: Error) -> Bool {
        if case APIClientError.httpError(let statusCode) = error {
            return statusCode == 404
        }
        return false
    }

    @MainActor
    private func startSpeech(for key: SpeechKey) async {
        viewModel.beginSpeech(for: key)
        isStartingMic = true
        defer { isStartingMic = false }
        if ttsService.isPlaying {
            ttsService.stop()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        resetTranscriptTranslation(for: key)
        viewModel.updateSpeechStatus(.connecting, for: key)
        let started = await speechService.startRecording(localeIdentifier: "zh-TW")
        guard viewModel.activeSpeechKey == key else {
            if speechService.isRecording {
                speechService.cancelRecording()
            }
            return
        }
        if started {
            viewModel.updateSpeechStatus(.listening, for: key)
        } else {
            let message = speechService.issue?.message ?? "Could not start the microphone."
            viewModel.failSpeech(for: key, message: message)
            performHaptic(.error)
        }
    }

    private func suppressNextGlossDismiss() {
        suppressGlossDismiss = true
        DispatchQueue.main.async {
            suppressGlossDismiss = false
        }
    }

    private func updateIsNearBottom() {
        let threshold: CGFloat = 120
        guard scrollViewHeight > 0 else {
            isNearBottom = true
            return
        }
        let distanceFromBottom = contentMetrics.height + contentMetrics.minY - scrollViewHeight
        isNearBottom = distanceFromBottom <= threshold
    }

    private var shouldPulseMic: Bool {
        guard let target = viewModel.currentPracticeTarget else { return false }
        if let attempt = viewModel.speechAttempts[target.key],
           attempt.status == .passed {
            return false
        }
        guard !ttsService.isPlaying else { return false }
        guard !ttsService.isLoading else { return false }
        guard !speechService.isRecording else { return false }
        guard !isStartingMic else { return false }
        guard viewModel.activeSpeechKey == nil else { return false }
        guard !viewModel.isLoadingTurn else { return false }
        return true
    }

    private var micAccessibilityLabel: String {
        if isStartingMic {
            return "Preparing microphone"
        }
        if speechService.isRecording {
            return "Stop recording"
        }
        return "Start recording"
    }

    private var micAccessibilityHint: String {
        if speechService.isRecording {
            return "Tap to stop recording"
        }
        if isStartingMic {
            return "Preparing microphone"
        }
        return "Tap to start recording"
    }

    private func updateMicPulseState() {
        guard shouldPulseMic else {
            isMicPulseExpanded = false
            return
        }

        guard !reduceMotion else {
            isMicPulseExpanded = false
            return
        }

        guard !isMicPulseExpanded else { return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            isMicPulseExpanded = true
        }
    }

    private enum MicHaptic {
        case start
        case stop
        case cancel
        case error
    }

    private func performHaptic(_ event: MicHaptic) {
        switch event {
        case .start:
            startHapticGenerator.impactOccurred(intensity: 1.0)
        case .stop:
            stopHapticGenerator.impactOccurred()
        case .cancel:
            cancelHapticGenerator.impactOccurred()
        case .error:
            errorHapticGenerator.notificationOccurred(.warning)
        }
    }

    private func prepareHaptic(for event: MicHaptic) {
        switch event {
        case .start:
            startHapticGenerator.prepare()
        case .stop:
            stopHapticGenerator.prepare()
        case .cancel:
            cancelHapticGenerator.prepare()
        case .error:
            errorHapticGenerator.prepare()
        }
    }

    private func prepareAllHaptics() {
        prepareHaptic(for: .start)
        prepareHaptic(for: .stop)
        prepareHaptic(for: .cancel)
        prepareHaptic(for: .error)
    }

    @MainActor
    private func resetTranscriptTranslation(for key: SpeechKey) {
        transcriptTranslations.removeValue(forKey: key)
    }

    @MainActor
    private func queueTranscriptTranslation(for key: SpeechKey, transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = transcriptTranslations[key],
           existing.transcript == trimmed,
           existing.meaning != nil || existing.isTranslating {
            return
        }

        transcriptTranslations[key] = TranscriptTranslation(
            transcript: trimmed,
            pinyin: trimmed.pinyinTranscription,
            meaning: nil,
            isTranslating: true,
            error: nil
        )
        transcriptTranslationQueue.send(
            TranscriptTranslationQueue.Request(key: key, transcript: trimmed)
        )
    }

    private func runTranscriptTranslationLoop(using session: TranslationSession) async {
        for await request in transcriptTranslationQueue.stream {
            if Task.isCancelled { break }
            await translateTranscript(request: request, session: session)
        }
    }

    @MainActor
    private func translateTranscript(
        request: TranscriptTranslationQueue.Request,
        session: TranslationSession
    ) async {
        guard let current = transcriptTranslations[request.key],
              current.transcript == request.transcript else { return }

        do {
            let translated = try await TranslationService.translateTraditionalChineseToEnglish(
                request.transcript,
                session: session
            )
            guard !Task.isCancelled else { return }
            guard var updated = transcriptTranslations[request.key],
                  updated.transcript == request.transcript else { return }
            updated.meaning = translated
            updated.isTranslating = false
            updated.error = nil
            transcriptTranslations[request.key] = updated
        } catch {
            guard !Task.isCancelled else { return }
            guard var updated = transcriptTranslations[request.key],
                  updated.transcript == request.transcript else { return }
            updated.isTranslating = false
            updated.error = "Unable to translate right now."
            transcriptTranslations[request.key] = updated
        }
    }
}

private struct MicHoldToSpeakButton: View {
    let shouldPulse: Bool
    let isPulseExpanded: Bool
    let reduceMotion: Bool
    let isRecording: Bool
    let isStartingMic: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let micButtonSize: CGSize
    let micCornerRadius: CGFloat
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if shouldPulse {
                RoundedRectangle(cornerRadius: micCornerRadius, style: .continuous)
                    .fill(AppColors.micPulseHalo.opacity(reduceMotion ? 0.3 : (isPulseExpanded ? 0.32 : 0.2)))
                    .frame(width: micButtonSize.width, height: micButtonSize.height)
                    .scaleEffect(reduceMotion ? 1.1 : (isPulseExpanded ? 1.18 : 1.06))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: micCornerRadius, style: .continuous)
                    .stroke(AppColors.micPulseHalo.opacity(reduceMotion ? 0.7 : 0.85), lineWidth: 5)
                    .frame(width: micButtonSize.width, height: micButtonSize.height)
                    .scaleEffect(reduceMotion ? 1.1 : (isPulseExpanded ? 1.18 : 1.06))
                    .opacity(reduceMotion ? 0.85 : (isPulseExpanded ? 0.2 : 0.7))
                    .shadow(color: AppColors.micPulseHalo.opacity(0.65), radius: 14, x: 0, y: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Button {
                onTap()
            } label: {
                Image(systemName: (isRecording || isStartingMic) ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.onAccent)
                    .frame(width: micButtonSize.width, height: micButtonSize.height)
                    .background(AppColors.accent, in: RoundedRectangle(cornerRadius: micCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: micCornerRadius, style: .continuous)
                            .stroke(AppColors.onAccent.opacity(0.25), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: micCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
        }
        .contentShape(RoundedRectangle(cornerRadius: micCornerRadius, style: .continuous))
    }
}

private struct SpeakSceneBottomBar: View {
    @Binding var isOutlinePresented: Bool
    let shouldPulse: Bool
    let isPulseExpanded: Bool
    let reduceMotion: Bool
    let isRecording: Bool
    let isStartingMic: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let micButtonSize: CGSize
    let micCornerRadius: CGFloat
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button {
                isOutlinePresented = true
            } label: {
                Image(systemName: "list.clipboard")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 68, height: 68)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Outline")

            Spacer()

            MicHoldToSpeakButton(
                shouldPulse: shouldPulse,
                isPulseExpanded: isPulseExpanded,
                reduceMotion: reduceMotion,
                isRecording: isRecording,
                isStartingMic: isStartingMic,
                accessibilityLabel: accessibilityLabel,
                accessibilityHint: accessibilityHint,
                micButtonSize: micButtonSize,
                micCornerRadius: micCornerRadius,
                onTap: onTap
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20
            )
            .fill(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct OutlinePanel: View {
    let outline: SpeakChatOutline

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(outline.turns) { turn in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Turn \(turn.step)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(sequence(for: turn), id: \.role) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.role)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(entry.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let tip = outline.practiceTip?.trimmingCharacters(in: .whitespacesAndNewlines),
               !tip.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Practice tip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tip)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func sequence(for turn: SpeakTurnOutline) -> [(role: String, text: String)] {
        if turn.speakFirst == .ai {
            return [("AI", turn.aiIntent), ("You", turn.userIntent)]
        }
        return [("You", turn.userIntent), ("AI", turn.aiIntent)]
    }
}

private struct ConversationPanel: View {
    let turns: [SpeakTurn]
    let isLoadingTurn: Bool
    let turnError: String?
    let speechAttempts: [SpeechKey: SpeechAttempt]
    let activeSpeechKey: SpeechKey?
    let activeTranscript: String
    let speechIssue: SpeechInputIssue?
    @ObservedObject var ttsService: TTSService
    let transcriptTranslations: [SpeechKey: TranscriptTranslation]
    @Binding var activeGlossSelection: GlossSelection?
    @Binding var revealedTranslations: Set<TranslationKey>
    let onGlossInteraction: () -> Void
    let onRetrySpeech: (SpeechKey) -> Void
    let onAcceptSpeech: (SpeechKey) -> Void
    let onDismissSpeechError: () -> Void
    let onNext: () -> Void
    let bottomSpacerHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if turns.isEmpty && !isLoadingTurn {
                Text("Tap Start to load the conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            ForEach(orderedTurns) { turn in
                VStack(alignment: .leading, spacing: 16) {
                    let sequence = lineSequence(for: turn)
                    ForEach(sequence.indices, id: \.self) { index in
                        let entry = sequence[index]
                        let key = TranslationKey(step: turn.step, role: entry.role)
                        let speechKey = SpeechKey(step: turn.step, role: entry.role)
                        let isActiveSpeech = activeSpeechKey == speechKey
                        let attempt = speechAttempts[speechKey]
                        let speechTranscript = isActiveSpeech
                        ? (activeTranscript.isEmpty ? attempt?.transcript : activeTranscript)
                        : attempt?.transcript
                        let trimmedTranscript = speechTranscript?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let translation = trimmedTranscript.isEmpty
                            ? nil
                            : transcriptTranslations[speechKey]
                        let resolvedTranslation = translation?.transcript == trimmedTranscript
                            ? translation
                            : nil
                        let speechStatus = attempt?.status ?? (isActiveSpeech ? .listening : nil)
                        ConversationBubble(
                            role: entry.role,
                            line: entry.line,
                            glossKey: speechKey,
                            speechTranscript: speechTranscript,
                            speechTranslation: resolvedTranslation,
                            speechStatus: speechStatus,
                            speechScore: attempt?.score,
                            isTranslationVisible: revealedTranslations.contains(key),
                            activeGlossSelection: $activeGlossSelection,
                            onGlossInteraction: onGlossInteraction,
                            onToggleTranslation: {
                                toggleTranslation(for: key)
                            },
                            onRetrySpeech: {
                                onRetrySpeech(speechKey)
                            },
                            onAcceptSpeech: {
                                onAcceptSpeech(speechKey)
                            },
                            onPlay: {
                                Task {
                                    await ttsService.play(text: entry.line.chinese)
                                }
                            },
                            isPlayDisabled: ttsService.isLoading || ttsService.isPlaying
                        )
                    }
                }
                .id(turn.step)
            }

            if isLoadingTurn {
                RotatingLoadingText(
                    phrases: [
                        "Loading next turn...",
                        "Fetching the next line...",
                        "Almost ready..."
                    ]
                )
                .accessibilityLabel("Loading next turn")
                .padding(.top, 8)
            }

            if let turnError {
                ErrorCard(message: turnError, actionTitle: "Try again", onAction: onNext)
            }

            if let speechIssue {
                if speechIssue.isPermission {
                    SpeechPermissionCard(issue: speechIssue, onDismiss: onDismissSpeechError)
                } else {
                    ErrorCard(message: speechIssue.message, actionTitle: "Dismiss", onAction: onDismissSpeechError)
                }
            }
            Color.clear
                .frame(height: bottomSpacerHeight)
                .id(ScrollAnchor.bottom)
        }
    }

    private var orderedTurns: [SpeakTurn] {
        turns.sorted { $0.step < $1.step }
    }

    private func lineSequence(for turn: SpeakTurn) -> [(role: SpeakRole, line: SpeakLine)] {
        if turn.speakFirst == .ai {
            return [(role: .ai, line: turn.aiLine), (role: .user, line: turn.userLine)]
        }
        return [(role: .user, line: turn.userLine), (role: .ai, line: turn.aiLine)]
    }

    private func toggleTranslation(for key: TranslationKey) {
        if revealedTranslations.contains(key) {
            revealedTranslations.remove(key)
        } else {
            revealedTranslations.insert(key)
        }
    }
}

private struct ConversationBubble: View {
    let role: SpeakRole
    let line: SpeakLine
    let glossKey: SpeechKey
    let speechTranscript: String?
    let speechTranslation: TranscriptTranslation?
    let speechStatus: SpeechAttemptStatus?
    let speechScore: Double?
    let isTranslationVisible: Bool
    @Binding var activeGlossSelection: GlossSelection?
    let onGlossInteraction: () -> Void
    let onToggleTranslation: () -> Void
    let onRetrySpeech: () -> Void
    let onAcceptSpeech: () -> Void
    let onPlay: () -> Void
    let isPlayDisabled: Bool
    @State private var calloutSize: CGSize = .zero

    var body: some View {
        let tokens = glossTokens
        let activeGlossIndex = activeGlossSelection?.key == glossKey ? activeGlossSelection?.tokenIndex : nil
        let glossBinding = Binding<Int?>(
            get: {
                activeGlossSelection?.key == glossKey ? activeGlossSelection?.tokenIndex : nil
            },
            set: { newValue in
                onGlossInteraction()
                if let newValue {
                    activeGlossSelection = GlossSelection(key: glossKey, tokenIndex: newValue)
                } else if activeGlossSelection?.key == glossKey {
                    activeGlossSelection = nil
                }
            }
        )
        HStack {
            if role == .user {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(line.chinese)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let tokens, !tokens.isEmpty {
                    PinyinGlossView(tokens: tokens, activeTokenIndex: glossBinding)
                } else if let pinyinText {
                    Text(pinyinText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let englishText, isTranslationVisible {
                    Text(englishText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if role == .user, let status = speechStatus {
                    let presentation = statusPresentation(for: status, score: speechScore)
                    VStack(alignment: .leading, spacing: 8) {
                        if let presentation {
                            HStack(spacing: 8) {
                                if presentation.showsSpinner {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                }
                                Text(presentation.text)
                                    .font(.footnote)
                                    .foregroundStyle(presentation.color)
                            }
                        }

                        if let transcript = speechTranscript, !transcript.isEmpty {
                            Text(highlightedTranscript(transcript))
                                .font(.body)

                            if let speechTranslation {
                                VStack(alignment: .leading, spacing: 4) {
                                    if !speechTranslation.pinyin.isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Pinyin")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(speechTranslation.pinyin)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .accessibilityLabel("Pinyin, \(speechTranslation.pinyin)")
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Meaning")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let meaning = speechTranslation.meaning, !meaning.isEmpty {
                                            Text(meaning)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .accessibilityLabel("Meaning, \(meaning)")
                                        } else if speechTranslation.isTranslating {
                                            Text("Translating...")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        } else if let error = speechTranslation.error {
                                            Text(error)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } else if case .cancelled = status {
                            Text("Cancelled.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else if case .error = status {
                            EmptyView()
                        } else if presentation?.showsSpinner == true {
                            EmptyView()
                        } else {
                            Text("Start speaking to compare your line.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if englishText != nil {
                    HStack(spacing: 8) {
                        Button {
                            onPlay()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play")
                        .disabled(isPlayDisabled)

                        Button {
                            onToggleTranslation()
                        } label: {
                            Image(systemName: "translate")
                                .font(.title3)
                                .foregroundStyle(isTranslationVisible ? AppColors.accent : .secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isTranslationVisible ? "Hide translation" : "Show translation")
                    }
                } else {
                    Button {
                        onPlay()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play")
                    .disabled(isPlayDisabled)
                }

                if role == .user, speechStatus == .failed {
                    HStack(spacing: 12) {
                        Button("Try again") {
                            onRetrySpeech()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button("Accept") {
                            onAcceptSpeech()
                        }
                        .neutralProminentButton()
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(20)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if activeGlossSelection?.key == glossKey {
                    activeGlossSelection = nil
                }
            }
            .overlayPreferenceValue(GlossTokenBoundsKey.self) { anchors in
                GlossCalloutOverlay(
                    anchors: anchors,
                    tokens: tokens,
                    activeGlossIndex: activeGlossIndex,
                    calloutSize: calloutSize
                )
            }
            .onChange(of: activeGlossSelection) { _, _ in
                calloutSize = .zero
            }
            .onPreferenceChange(GlossCalloutSizeKey.self) { size in
                calloutSize = size
            }

            if role == .ai {
                Spacer(minLength: 36)
            }
        }
    }

    private var cardBackground: Color {
        role == .ai ? AppColors.accentSubtle : Color(.secondarySystemGroupedBackground)
    }

    private var pinyinText: String? {
        let trimmed = line.pinyin.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var glossTokens: [SpeakGlossToken]? {
        let trimmed = line.gloss.filter { !$0.pinyin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return trimmed.isEmpty ? nil : trimmed
    }

    private var englishText: String? {
        let trimmed = line.english.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct StatusPresentation {
        let text: String
        let color: Color
        let showsSpinner: Bool
    }

    private func statusPresentation(for status: SpeechAttemptStatus, score: Double?) -> StatusPresentation? {
        switch status {
        case .preparing:
            return StatusPresentation(text: "Preparing mic...", color: .secondary, showsSpinner: true)
        case .connecting:
            return StatusPresentation(text: "Connecting...", color: .secondary, showsSpinner: true)
        case .listening:
            return StatusPresentation(text: "Listening...", color: .secondary, showsSpinner: true)
        case .processing:
            return StatusPresentation(text: "Processing...", color: .secondary, showsSpinner: true)
        case .passed:
            let text: String
            if let score {
                text = "Matched (\(Int(score * 100))%)"
            } else {
                text = "Matched"
            }
            return StatusPresentation(text: text, color: .green, showsSpinner: false)
        case .failed:
            let text: String
            if let score {
                text = "Try again (\(Int(score * 100))%)"
            } else {
                text = "Try again"
            }
            return StatusPresentation(text: text, color: .secondary, showsSpinner: false)
        case .cancelled:
            return StatusPresentation(text: "Cancelled", color: .secondary, showsSpinner: false)
        case .error(let message):
            return StatusPresentation(text: message, color: .red, showsSpinner: false)
        }
    }

    private func highlightedTranscript(_ transcript: String) -> AttributedString {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = line.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptChars = Array(trimmed)
        let targetChars = Array(target)
        var attributed = AttributedString()

        for index in transcriptChars.indices {
            let character = String(transcriptChars[index])
            var segment = AttributedString(character)
            let isMatch = index < targetChars.count && transcriptChars[index] == targetChars[index]
            segment.foregroundColor = isMatch ? .primary : .red
            attributed.append(segment)
        }

        return attributed
    }

}

private struct GlossCalloutOverlay: View {
    let anchors: [Int: Anchor<CGRect>]
    let tokens: [SpeakGlossToken]?
    let activeGlossIndex: Int?
    let calloutSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            if let activeGlossIndex,
               let tokens,
               tokens.indices.contains(activeGlossIndex),
               let anchor = anchors[activeGlossIndex] {
                let english = tokens[activeGlossIndex].english
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let frame = proxy[anchor]
                let maxWidth = min(220, proxy.size.width - 16)
                let measuredWidth = calloutSize.width > 0 ? calloutSize.width : maxWidth
                let centerX = min(
                    max(frame.midX, measuredWidth / 2 + 8),
                    proxy.size.width - measuredWidth / 2 - 8
                )
                let centerY = calloutCenterY(frame: frame, proxySize: proxy.size)

                if !english.isEmpty {
                    GlossCallout(text: english, maxWidth: maxWidth)
                        .background(
                            GeometryReader { calloutProxy in
                                Color.clear.preference(
                                    key: GlossCalloutSizeKey.self,
                                    value: calloutProxy.size
                                )
                            }
                        )
                        .position(x: centerX, y: centerY)
                        .allowsHitTesting(false)
                        .zIndex(1)
                }
            }
        }
    }

    private func calloutCenterY(frame: CGRect, proxySize: CGSize) -> CGFloat {
        let height = calloutSize.height > 0 ? calloutSize.height : 32
        let aboveY = frame.minY - height - 8
        let belowY = frame.maxY + 8
        let canPlaceAbove = aboveY >= 8
        let originY = canPlaceAbove ? aboveY : belowY
        let clampedY = min(max(originY, 8), proxySize.height - height - 8)
        return clampedY + height / 2
    }
}

private struct TranslationKey: Hashable {
    let step: Int
    let role: SpeakRole
}

private struct GlossSelection: Hashable {
    let key: SpeechKey
    let tokenIndex: Int
}

private struct TranscriptTranslation: Equatable {
    let transcript: String
    let pinyin: String
    var meaning: String?
    var isTranslating: Bool
    var error: String?
}

private final class TranscriptTranslationQueue {
    struct Request {
        let key: SpeechKey
        let transcript: String
    }

    let stream: AsyncStream<Request>
    private var continuation: AsyncStream<Request>.Continuation?

    init() {
        var localContinuation: AsyncStream<Request>.Continuation?
        stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        continuation = localContinuation
    }

    func send(_ request: Request) {
        continuation?.yield(request)
    }

    func finish() {
        continuation?.finish()
    }
}

private struct PinyinGlossView: View {
    let tokens: [SpeakGlossToken]
    @Binding var activeTokenIndex: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    activeTokenIndex = nil
                }

            TagFlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    let english = token.english.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isMeaningful = !(token.isPunctuation ?? false) && !english.isEmpty
                    let isActive = activeTokenIndex == index

                    if isMeaningful {
                        Button {
                            activeTokenIndex = activeTokenIndex == index ? nil : index
                        } label: {
                            Text(attributedPinyin(token.pinyin))
                                .font(.title3)
                                .foregroundStyle(isActive ? .primary : .secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isActive ? Color.primary.opacity(0.12) : .clear)
                        )
                        .accessibilityLabel("\(token.pinyin), \(english)")
                        .anchorPreference(key: GlossTokenBoundsKey.self, value: .bounds) {
                            [index: $0]
                        }
                    } else {
                        Text(token.pinyin)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }
}

    private func attributedPinyin(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.underlineColor = UIColor.secondaryLabel
        attributed.underlineStyle = .single.union(.patternDot)
        return attributed
    }
}

private struct GlossTokenBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct GlossCalloutSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct GlossCallout: View {
    let text: String
    let maxWidth: CGFloat
    @State private var measuredTextSize: CGSize = .zero

    var body: some View {
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 8
        let targetWidth = measuredTextSize.width > 0
            ? min(measuredTextSize.width + horizontalPadding * 2, maxWidth)
            : maxWidth

        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: targetWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .overlay(
                Text(text)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: true)
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: GlossCalloutTextSizeKey.self,
                                value: proxy.size
                            )
                        }
                    )
                    .accessibilityHidden(true)
            )
            .onPreferenceChange(GlossCalloutTextSizeKey.self) { size in
                if size != .zero {
                    measuredTextSize = size
                }
            }
    }
}

private struct GlossCalloutTextSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct ScrollContentMetrics: Equatable {
    let height: CGFloat
    let minY: CGFloat

    static let zero = ScrollContentMetrics(height: 0, minY: 0)
}

private struct ScrollContentMetricsKey: PreferenceKey {
    static var defaultValue: ScrollContentMetrics = .zero

    static func reduce(value: inout ScrollContentMetrics, nextValue: () -> ScrollContentMetrics) {
        value = nextValue()
    }
}

private struct ScrollViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum ScrollAnchor {
    static let bottom = "conversation-scroll-bottom"
}

private struct ErrorCard: View {
    let message: String
    var actionTitle: String = "Try again"
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            Button(actionTitle) {
                onAction()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SpeechPermissionCard: View {
    @Environment(\.openURL) private var openURL
    let issue: SpeechInputIssue
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: issue.iconName)
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)

                Text(issue.title)
                    .font(.headline)
            }

            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if issue.showsSettingsAction {
                    Button("Open Settings") {
                        openSettings()
                    }
                    .neutralProminentButton()
                }

                Button(issue.showsSettingsAction ? "Not now" : "Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview {
    SpeakSceneDetailView(scene: SpeakScene(
        id: UUID(),
        title: "Order bubble tea",
        description: "Practice ordering a drink with sugar and ice preferences.",
        tags: [],
        level: .beginner,
        createdAt: nil
    )) { _ in }
    .environmentObject(AuthManager.shared)
}
