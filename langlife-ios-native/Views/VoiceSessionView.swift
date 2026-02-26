import SwiftUI

struct VoiceSessionView: View {
    @StateObject private var viewModel = VoiceSessionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    transcriptArea
                    statusBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End") {
                        viewModel.endSession()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isConversationActive)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .navigationTitle("Voice Practice")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: viewModel.state) { _, newState in
            if case .showingResults = newState {
                // Handled by conditional view below
            }
        }
        .fullScreenCover(isPresented: showingResults) {
            VoiceSessionResultsView(
                transcript: viewModel.transcript,
                durationSeconds: sessionDuration,
                totalTurns: viewModel.transcript.filter { $0.role == .user }.count,
                newCards: viewModel.completionResponse?.newCards ?? []
            )
        }
    }

    private var showingResults: Binding<Bool> {
        Binding(
            get: { viewModel.state == .showingResults },
            set: { if !$0 { dismiss() } }
        )
    }

    private var sessionDuration: Int {
        viewModel.transcript.isEmpty ? 0 : {
            guard let first = viewModel.transcript.first?.timestamp,
                  let last = viewModel.transcript.last?.timestamp else { return 0 }
            return max(1, Int(last.timeIntervalSince(first)))
        }()
    }

    private var isConversationActive: Bool {
        if case .conversationActive = viewModel.state {
            return true
        }
        return false
    }

    // MARK: - Transcript

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.transcript) { entry in
                        TranscriptBubble(entry: entry)
                            .id(entry.id)
                    }

                    if !viewModel.currentAgentText.isEmpty {
                        TranscriptBubble(
                            entry: VoiceTranscriptEntry(role: .agent, text: viewModel.currentAgentText)
                        )
                        .opacity(0.7)
                        .id("streaming")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.transcript.count) { _, _ in
                withAnimation {
                    if let last = viewModel.transcript.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentAgentText) { _, _ in
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 12) {
            Divider()

            Group {
                switch viewModel.state {
                case .conversationActive(.readyToSpeak):
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppColors.micPulse)
                            .frame(width: 12, height: 12)
                            .modifier(PulseAnimation())
                        Text("Hold to speak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .conversationActive(.recording):
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 12, height: 12)
                        Text("Recording... release to send")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .conversationActive(.agentSpeaking):
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundStyle(AppColors.accent)
                            .symbolEffect(.variableColor.iterative)
                        Text("Speaking... hold to interrupt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .conversationActive(.processing):
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Retry") {
                            viewModel.retryProcessingTurn()
                        }
                        .font(.caption.weight(.semibold))
                    }

                case .connecting(let stage):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(stage.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .endingSession:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving session...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .error(let message):
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)

                        if message.contains("Settings") {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.subheadline)
                        }
                    }

                default:
                    EmptyView()
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)

            if isConversationActive {
                PushToSpeakButton(
                    isEnabled: viewModel.isPushToSpeakEnabled,
                    isPressed: viewModel.isPushToSpeakPressed,
                    onPressBegan: { viewModel.beginPushToSpeak() },
                    onPressEnded: { viewModel.endPushToSpeak() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Spacer()
                    .frame(height: 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - Transcript Bubble

private struct TranscriptBubble: View {
    let entry: VoiceTranscriptEntry

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 60) }

            Text(entry.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    entry.role == .agent
                        ? AppColors.accentSubtle
                        : AppColors.accent
                )
                .foregroundStyle(entry.role == .agent ? Color.primary : AppColors.onAccent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if entry.role == .agent { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Pulse Animation

private struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

private struct PushToSpeakButton: View {
    let isEnabled: Bool
    let isPressed: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void

    @State private var isGesturePressing = false

    var body: some View {
        let pressGesture = DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled else { return }
                guard !isGesturePressing else { return }
                isGesturePressing = true
                onPressBegan()
            }
            .onEnded { _ in
                guard isGesturePressing else { return }
                isGesturePressing = false
                onPressEnded()
            }

        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isPressed ? AppColors.micPulse : AppColors.accent)
            .overlay(
                HStack(spacing: 8) {
                    Image(systemName: isPressed ? "stop.fill" : "mic.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(isPressed ? "Release to send" : "Hold to speak")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(AppColors.onAccent)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .opacity((isEnabled || isPressed) ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .gesture(pressGesture)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isGesturePressing {
                    isGesturePressing = false
                    onPressEnded()
                }
            }
            .onDisappear {
                if isGesturePressing {
                    isGesturePressing = false
                    onPressEnded()
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Hold to speak")
            .accessibilityHint("Press and hold to record. Release to send.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isPressed {
                    onPressEnded()
                } else if isEnabled {
                    onPressBegan()
                }
            }
    }
}
