import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @AppStorage("hskLevel") private var hskLevel = 0
    @State private var selection = 0
    @State private var selectedLevel: HSKLevel = .hsk1

    private let steps = OnboardingStep.allCases

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                header

                TabView(selection: $selection) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingPageView(step: step, selectedLevel: $selectedLevel)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                footer
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Lang Life")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            if selection < steps.count - 1 {
                Button("Skip") {
                    onFinish()
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                advance()
            } label: {
                Text(selection == steps.count - 1 ? "Get started" : "Continue")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .neutralProminentButton()
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func advance() {
        if selection < steps.count - 1 {
            selection += 1
        } else {
            hskLevel = selectedLevel.rawValue
            if authManager.user != nil {
                Task {
                    try? await UserProfileRepository().syncHSKLevel(selectedLevel.rawValue)
                }
            }
            onFinish()
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case immersion
    case generateScenes
    case autoCards
    case addCards
    case hskLevel

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immersion:
            return "Immersion, on demand"
        case .generateScenes:
            return "Generate scenes to speak"
        case .autoCards:
            return "Cards appear automatically"
        case .addCards:
            return "Add your own cards"
        case .hskLevel:
            return "Choose your level"
        }
    }

    var subtitle: String {
        switch self {
        case .immersion:
            return "Lang Life uses AI to recreate real situations so practice feels like being there."
        case .generateScenes:
            return "Describe a moment and Lang Life builds a speaking script you can jump into."
        case .autoCards:
            return "New words from each scene turn into flashcards for review."
        case .addCards:
            return "Save the phrases you want and practice them anytime."
        case .hskLevel:
            return "Pick an HSK level to start with. You can change it later in Settings."
        }
    }
}

private struct OnboardingPageView: View {
    let step: OnboardingStep
    @Binding var selectedLevel: HSKLevel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            hero

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(step.subtitle)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var hero: some View {
        switch step {
        case .immersion:
            ImmersionHero()
        case .generateScenes:
            SceneGeneratorHero()
        case .autoCards:
            AutoCardsHero()
        case .addCards:
            AddCardsHero()
        case .hskLevel:
            HSKLevelPickerHero(selectedLevel: $selectedLevel)
        }
    }
}

private struct ImmersionHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("AI immersion")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            HStack {
                ChatBubble(
                    english: "How are you?",
                    mandarin: "你好嗎？",
                    pinyin: "nǐ hǎo ma?",
                    isAccent: true
                )
                Spacer(minLength: 16)
            }

            HStack {
                Spacer(minLength: 16)
                ChatBubble(
                    english: "I'm good, thanks.",
                    mandarin: "我很好，謝謝。",
                    pinyin: "wǒ hěn hǎo, xiè xiè.",
                    isAccent: false
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
        .offset(y: reduceMotion ? 0 : (isFloating ? -6 : 6))
        .onAppear {
            if !reduceMotion {
                isFloating = true
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
            value: isFloating
        )
    }
}

private struct SceneGeneratorHero: View {
    @State private var didGenerate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                Text("Scene prompt")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Text("Ask for some water")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Divider()

            if didGenerate {
                VStack(alignment: .leading, spacing: 10) {
                    TranscriptLine(
                        speaker: "You",
                        english: "Can I have some water please",
                        mandarin: "可以給我一些水嗎？",
                        pinyin: "kě yǐ gěi wǒ yī xiē shuǐ ma?"
                    )

                    TranscriptLine(
                        speaker: "AI",
                        english: "Sure. Still or sparkling?",
                        mandarin: "好的。一般的水還是氣泡水？",
                        pinyin: "hǎo de. yī bān de shuǐ hái shì qì pào shuǐ?"
                    )
                }
            } else {
                Text("Tap generate to preview the scene.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    didGenerate.toggle()
                }
            } label: {
                Label(didGenerate ? "Regenerate" : "Generate", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
    }
}

private struct AutoCardsHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentIndex = 0

    private let cards: [OnboardingCard] = [
        OnboardingCard(
            english: "How are you?",
            mandarin: "你好嗎？",
            pinyin: "nǐ hǎo ma?"
        ),
        OnboardingCard(
            english: "I'm good, thanks.",
            mandarin: "我很好，謝謝。",
            pinyin: "wǒ hěn hǎo, xiè xiè."
        ),
        OnboardingCard(
            english: "And you?",
            mandarin: "你呢？",
            pinyin: "nǐ ne?"
        )
    ]

    private var currentCard: OnboardingCard {
        cards[currentIndex]
    }

    private var nextCard: OnboardingCard {
        cards[(currentIndex + 1) % cards.count]
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                StudyCardPreview(
                    chinese: nextCard.mandarin,
                    pinyin: nextCard.pinyin,
                    english: nextCard.english
                )
                .scaleEffect(0.94)
                .offset(x: 12, y: 12)
                .opacity(0.6)

                StudyCardPreview(
                    chinese: currentCard.mandarin,
                    pinyin: currentCard.pinyin,
                    english: currentCard.english
                )
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)

            HStack(spacing: 12) {
                Button {
                    advanceCard()
                } label: {
                    Text("Again")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    advanceCard()
                } label: {
                    Text("Easy")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .neutralProminentButton()
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
    }

    private func advanceCard() {
        let nextIndex = (currentIndex + 1) % cards.count
        if reduceMotion {
            currentIndex = nextIndex
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                currentIndex = nextIndex
            }
        }
    }
}

private struct AddCardsHero: View {
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New card")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        isSaved.toggle()
                    }
                } label: {
                    Label(isSaved ? "Saved" : "Add", systemImage: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(isSaved ? .green : .primary)
                }
                .buttonStyle(.plain)
            }

            FieldRow(title: "English", value: "How are you?")
            FieldRow(title: "Pinyin", value: "nǐ hǎo ma?")
            FieldRow(title: "Chinese", value: "你好嗎？")

            Text(isSaved ? "Card saved for practice." : "Tap the plus to save your own cards.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
    }
}

private struct HSKLevelPickerHero: View {
    @Binding var selectedLevel: HSKLevel
    @State private var isHSKInfoPresented = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(HSKLevel.allCases, id: \.rawValue) { level in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedLevel = level
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(level.displayName)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))

                            Text(level.description)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text("\(level.cumulativeWordCount) words")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if selectedLevel == level {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                selectedLevel == level ? AppColors.accent : Color(.separator).opacity(0.2),
                                lineWidth: selectedLevel == level ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if AppConfig.hskInfoURL != nil {
                Button {
                    isHSKInfoPresented = true
                } label: {
                    Label("Learn more about HSK", systemImage: "info.circle")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $isHSKInfoPresented) {
            if let hskInfoURL = AppConfig.hskInfoURL {
                InAppSafariView(url: hskInfoURL)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
    }
}

private struct ChatBubble: View {
    let english: String
    let mandarin: String
    let pinyin: String
    let isAccent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mandarin)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(isAccent ? AppColors.onAccent : .primary)

            Text(pinyin)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isAccent ? AppColors.onAccent.opacity(0.9) : .secondary)

            Text(english)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isAccent ? AppColors.onAccent.opacity(0.85) : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isAccent ? AppColors.accent : Color(.systemBackground))
        )
        .accessibilityLabel("\(english). \(mandarin). \(pinyin)")
    }
}

private struct StudyCardPreview: View {
    let chinese: String
    let pinyin: String
    let english: String

    var body: some View {
        VStack(spacing: 10) {
            Text(chinese)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(pinyin)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text(english)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private struct OnboardingCard {
    let english: String
    let mandarin: String
    let pinyin: String
}

private struct TranscriptLine: View {
    let speaker: String
    let english: String
    let mandarin: String
    let pinyin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(speaker): \(english)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text(mandarin)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text(pinyin)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }
}
