import SwiftUI

struct SpeakSceneDetailView: View {
    @StateObject private var viewModel = SpeakSceneDetailViewModel()
    @StateObject private var ttsService = TTSService()
    @State private var revealedTranslations: Set<TranslationKey> = []
    @State private var isOutlinePresented = false
    let scene: SpeakScene

    var body: some View {
        sceneContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(scene.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: scene.id) {
            await viewModel.loadOutline(scene: scene)
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
                        ttsService: ttsService,
                        revealedTranslations: $revealedTranslations,
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
            ZStack {
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
                    Button("Next") {
                        Task {
                            await viewModel.loadNextTurn()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(viewModel.isLoadingTurn || viewModel.nextStep == nil)
                }

                Button {
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.onAccent)
                        .frame(width: 68, height: 68)
                        .background(AppColors.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
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
    @ObservedObject var ttsService: TTSService
    @Binding var revealedTranslations: Set<TranslationKey>
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
                    ConversationBubble(
                        role: entry.role,
                        line: entry.line,
                        isTranslationVisible: revealedTranslations.contains(key),
                        onToggleTranslation: {
                            toggleTranslation(for: key)
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
    let isTranslationVisible: Bool
    let onToggleTranslation: () -> Void
    let onPlay: () -> Void
    let isPlayDisabled: Bool

    var body: some View {
        HStack {
            if role == .user {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(line.chinese)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let pinyinText {
                    Text(pinyinText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let englishText, isTranslationVisible {
                    Text(englishText)
                        .font(.body)
                        .foregroundStyle(.secondary)
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
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(20)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

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

    private var englishText: String? {
        let trimmed = line.english.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TranslationKey: Hashable {
    let step: Int
    let role: SpeakRole
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
