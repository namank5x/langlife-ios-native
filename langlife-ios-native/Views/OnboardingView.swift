import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var selection = 0

    private let steps = OnboardingStep.allCases

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                header

                TabView(selection: $selection) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingPageView(step: step)
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
            onFinish()
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case immersion
    case generateScenes
    case autoCards
    case addCards

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
        }
    }
}

private struct OnboardingPageView: View {
    let step: OnboardingStep

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
                    text: "Welcome to the cafe. Ready to order?",
                    isAccent: true
                )
                Spacer(minLength: 16)
            }

            HStack {
                Spacer(minLength: 16)
                ChatBubble(
                    text: "Yes, a bubble tea with less ice.",
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

            Text("Order bubble tea with less ice")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Divider()

            Text(
                didGenerate
                    ? "AI: What size would you like?\nYou: Medium, less ice."
                    : "Tap generate to preview the scene."
            )
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

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
    @State private var isFlipped = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TokenChip(text: "bubble tea")
                TokenChip(text: "less ice")
                TokenChip(text: "medium")
            }

            ZStack {
                FlashcardStack(
                    title: "bubble tea",
                    subtitle: "zhen zhu nai cha",
                    isAccent: false
                )
                .offset(x: 12, y: 12)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isFlipped.toggle()
                    }
                } label: {
                    FlashcardStack(
                        title: isFlipped ? "zhen zhu nai cha" : "bubble tea",
                        subtitle: isFlipped ? "bubble tea" : "zhen zhu nai cha",
                        isAccent: true
                    )
                }
                .buttonStyle(.plain)
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

            FieldRow(title: "English", value: "bubble tea")
            FieldRow(title: "Pinyin", value: "zhen zhu nai cha")
            FieldRow(title: "Chinese", value: "zhen zhu nai cha")

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

private struct ChatBubble: View {
    let text: String
    let isAccent: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isAccent ? AppColors.onAccent : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 240, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isAccent ? AppColors.accent : Color(.systemBackground))
            )
    }
}

private struct TokenChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.systemBackground))
            )
    }
}

private struct FlashcardStack: View {
    let title: String
    let subtitle: String
    let isAccent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(isAccent ? AppColors.onAccent : .primary)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(isAccent ? AppColors.onAccent.opacity(0.9) : .secondary)
        }
        .padding(16)
        .frame(width: 210, height: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isAccent ? AppColors.accent : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
        )
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
