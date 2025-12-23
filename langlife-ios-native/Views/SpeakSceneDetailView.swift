import SwiftUI
import UIKit

struct SpeakSceneDetailView: View {
    @StateObject private var viewModel = SpeakSceneDetailViewModel()
    @StateObject private var ttsService = TTSService()
    @StateObject private var speechService = SpeechInputService()
    @State private var revealedTranslations: Set<TranslationKey> = []
    @State private var isOutlinePresented = false
    @State private var lastAutoPlayedStep: Int?
    let scene: SpeakScene

    var body: some View {
        sceneContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(scene.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: scene.id) {
            speechService.reset()
            lastAutoPlayedStep = nil
            await viewModel.loadOutline(scene: scene)
        }
        .onChange(of: speechService.partialTranscript) { _, transcript in
            guard speechService.isRecording, let key = viewModel.activeSpeechKey else { return }
            viewModel.updateSpeechTranscript(transcript, for: key)
        }
        .onChange(of: speechService.finalTranscript) { _, transcript in
            guard let transcript, let key = viewModel.activeSpeechKey else { return }
            guard viewModel.speechAttempts[key]?.status == .listening else { return }
            guard let line = viewModel.line(for: key) else { return }
            Task {
                await viewModel.finalizeSpeech(transcript: transcript, target: line.chinese, for: key)
            }
        }
        .onChange(of: speechService.errorMessage) { _, message in
            guard message != nil, let key = viewModel.activeSpeechKey else { return }
            viewModel.cancelSpeech(for: key)
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

    private var outlineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoadingOutline && viewModel.outline == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let outline = viewModel.outline {
                    OutlinePanel(outline: outline)
                } else if let error = viewModel.outlineError {
                    ErrorCard(message: error) {
                        Task {
                            await viewModel.loadOutline(scene: scene)
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

    private var sceneContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoadingOutline && viewModel.outline == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if viewModel.outline == nil, let error = viewModel.outlineError {
                    ErrorCard(message: error) {
                        Task {
                            await viewModel.loadOutline(scene: scene)
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
                        speechError: speechService.errorMessage,
                        ttsService: ttsService,
                        revealedTranslations: $revealedTranslations,
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
                        }
                    )
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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

                Button {
                    Task {
                        await handleMicTap()
                    }
                } label: {
                    Image(systemName: speechService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.onAccent)
                        .frame(width: 132, height: 64)
                        .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record")
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

    private func handleMicTap() async {
        if speechService.isRecording {
            speechService.stopAndFinalize()
            return
        }

        guard let target = viewModel.currentPracticeTarget else { return }
        if ttsService.isPlaying {
            ttsService.stop()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        viewModel.beginSpeech(for: target.key)
        let started = await speechService.startRecording(localeIdentifier: "zh-TW")
        if !started {
            viewModel.cancelSpeech(for: target.key)
        }
    }

    private func startSpeech(for key: SpeechKey) async {
        if ttsService.isPlaying {
            ttsService.stop()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        viewModel.beginSpeech(for: key)
        let started = await speechService.startRecording(localeIdentifier: "zh-TW")
        if !started {
            viewModel.cancelSpeech(for: key)
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
    let speechError: String?
    @ObservedObject var ttsService: TTSService
    @Binding var revealedTranslations: Set<TranslationKey>
    let onRetrySpeech: (SpeechKey) -> Void
    let onAcceptSpeech: (SpeechKey) -> Void
    let onDismissSpeechError: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if turns.isEmpty && !isLoadingTurn {
                Text("Tap Start to load the conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            ForEach(orderedTurns) { turn in
                let sequence = lineSequence(for: turn)
                ForEach(Array(sequence.enumerated()), id: \.offset) { _, entry in
                    let key = TranslationKey(step: turn.step, role: entry.role)
                    let speechKey = SpeechKey(step: turn.step, role: entry.role)
                    let isActiveSpeech = activeSpeechKey == speechKey
                    let attempt = speechAttempts[speechKey]
                    let speechTranscript = isActiveSpeech
                    ? (activeTranscript.isEmpty ? attempt?.transcript : activeTranscript)
                    : attempt?.transcript
                    let speechStatus = isActiveSpeech ? .listening : attempt?.status
                    ConversationBubble(
                        role: entry.role,
                        line: entry.line,
                        speechTranscript: speechTranscript,
                        speechStatus: speechStatus,
                        speechScore: attempt?.score,
                        isTranslationVisible: revealedTranslations.contains(key),
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

            if isLoadingTurn {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if let turnError {
                ErrorCard(message: turnError, actionTitle: "Try again", onAction: onNext)
            }

            if let speechError {
                ErrorCard(message: speechError, actionTitle: "Dismiss", onAction: onDismissSpeechError)
            }

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
    let speechTranscript: String?
    let speechStatus: SpeechAttemptStatus?
    let speechScore: Double?
    let isTranslationVisible: Bool
    let onToggleTranslation: () -> Void
    let onRetrySpeech: () -> Void
    let onAcceptSpeech: () -> Void
    let onPlay: () -> Void
    let isPlayDisabled: Bool
    @State private var activeGlossIndex: Int?
    @State private var calloutSize: CGSize = .zero

    var body: some View {
        let tokens = glossTokens
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
                    PinyinGlossView(tokens: tokens, activeTokenIndex: $activeGlossIndex)
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(status == .listening ? "Listening..." : "You said")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let transcript = speechTranscript, !transcript.isEmpty {
                            Text(highlightedTranscript(transcript))
                                .font(.body)
                        } else {
                            Text("Start speaking to compare your line.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        if let label = statusLabel(for: status, score: speechScore) {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(status == .passed ? .green : .secondary)
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
            .overlayPreferenceValue(GlossTokenBoundsKey.self) { anchors in
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
            .onChange(of: activeGlossIndex) { _, _ in
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

    private func statusLabel(for status: SpeechAttemptStatus, score: Double?) -> String? {
        switch status {
        case .listening:
            return nil
        case .passed:
            if let score {
                return "Great job (\(Int(score * 100))%)"
            }
            return "Great job"
        case .failed:
            if let score {
                return "Almost there (\(Int(score * 100))%)"
            }
            return "Almost there"
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

#Preview {
    SpeakSceneDetailView(scene: SpeakScene(
        id: UUID(),
        title: "Order bubble tea",
        description: "Practice ordering a drink with sugar and ice preferences.",
        tags: [],
        level: .beginner
    ))
}
