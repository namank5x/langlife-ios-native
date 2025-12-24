//
//  StudyView.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import Auth
import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var isAddCardPresented: Bool
    @Binding var isAddCardEnabled: Bool

    @State private var cards: [Flashcard] = []
    @State private var queue: [QueuedCard] = []
    @State private var isRevealed = false
    @State private var consecutiveFailures = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSavingCard = false
    @State private var addCardError: String?

    @StateObject private var ttsService = TTSService()

    private let repository = FlashcardRepository()
    private let actionButtonHeight: CGFloat = 48

    private var currentCard: Flashcard? {
        queue.first?.card
    }

    private var shouldShowReviewActions: Bool {
        currentCard != nil && isRevealed
    }

    var body: some View {
        VStack {
            Spacer(minLength: 24)

            if isLoading {
                ProgressView()
            } else if let card = currentCard {
                VStack(spacing: 16) {
                    Button {
                        revealAnswerIfNeeded()
                    } label: {
                        VStack(spacing: 16) {
                            Text(card.chinese)
                                .font(.system(size: 48, weight: .semibold))
                                .multilineTextAlignment(.center)

                            Text(card.pinyin)
                                .font(.title2)
                                .foregroundStyle(.secondary)

                            if isRevealed {
                                Text(card.english)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Tap to reveal")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRevealed ? "Answer revealed" : "Reveal answer")

                    Button {
                        Task {
                            await ttsService.play(text: card.chinese)
                        }
                    } label: {
                        Label(ttsService.isPlaying ? "Playing" : "Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                    }
                    .neutralProminentButton()
                    .controlSize(.large)
                    .accessibilityLabel("Play pronunciation")
                    .disabled(isLoading || ttsService.isLoading)

                    if shouldShowReviewActions {
                        HStack(spacing: 12) {
                            Button {
                                handleRate(.again)
                            } label: {
                                Text("Again")
                                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                // "Easy" maps to Good for a more conservative schedule.
                                handleRate(.good)
                            } label: {
                                Text("Easy")
                                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                            }
                            .neutralProminentButton()
                        }
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    Text("All done!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("You have completed your queue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Start Again") {
                        startAgain()
                    }
                    .neutralProminentButton()
                    .controlSize(.large)
                }
                .padding(.horizontal, 20)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isAddCardPresented) {
            AddCardSheet(
                isSaving: isSavingCard,
                errorMessage: addCardError,
                onSave: { chinese, pinyin, english in
                    await addCard(chinese: chinese, pinyin: pinyin, english: english)
                },
                onUpdate: {
                    addCardError = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadCardIfNeeded()
        }
        .onAppear {
            updateAddCardAvailability()
        }
        .onChange(of: isLoading) { _, _ in
            updateAddCardAvailability()
        }
        .onChange(of: isSavingCard) { _, _ in
            updateAddCardAvailability()
        }
        .onChange(of: isAddCardPresented) { _, newValue in
            if newValue {
                addCardError = nil
            }
        }
        .onChange(of: authManager.user?.id) { _, _ in
            Task {
                await loadCardIfNeeded()
            }
        }
        .onChange(of: currentCard?.id) { _, _ in
            isRevealed = false
        }
    }

    @MainActor
    private func loadCardIfNeeded() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        if let userId = authManager.user?.id {
            do {
                let fetchedCards = try await repository.fetchCards(for: userId)
                if fetchedCards.isEmpty {
                    let seeded = FlashcardSeed.defaults.map(Flashcard.initial(from:))
                    try await repository.insert(cards: seeded, userId: userId)
                    LocalFlashcardStore.clear()
                    cards = seeded
                } else {
                    cards = fetchedCards
                }
                queue = StudyQueue.buildQueue(cards)
                isRevealed = false
                consecutiveFailures = 0
            } catch {
                errorMessage = "Could not load cards. Showing local data instead."
                loadFromLocalFallback()
            }
            return
        }

        loadFromLocalFallback()
    }

    @MainActor
    private func loadFromLocalFallback() {
        if let local = LocalFlashcardStore.load(), !local.isEmpty {
            cards = local
            queue = StudyQueue.buildQueue(cards)
            isRevealed = false
            consecutiveFailures = 0
            return
        }

        let seeded = FlashcardSeed.defaults.map(Flashcard.initial(from:))
        LocalFlashcardStore.save(seeded)
        cards = seeded
        queue = StudyQueue.buildQueue(cards)
        isRevealed = false
        consecutiveFailures = 0
    }

    @MainActor
    private func persistReview(_ updatedCard: Flashcard) async {
        if let userId = authManager.user?.id {
            do {
                try await repository.update(card: updatedCard, userId: userId)
            } catch {
                errorMessage = "Could not save progress. Please try again."
            }
            return
        }

        LocalFlashcardStore.save(cards)
    }

    private func revealAnswerIfNeeded() {
        guard !isRevealed else { return }
        isRevealed = true
    }

    private func handleRate(_ rating: Rating) {
        guard let card = currentCard else { return }

        let updatedCard = FSRS.reviewCard(card, rating: rating)
        cards = cards.map { $0.id == updatedCard.id ? updatedCard : $0 }

        if rating == .again {
            let position = StudyQueue.getReinsertPosition(consecutiveFailures: consecutiveFailures + 1)
            queue = StudyQueue.reinsertCard(queue, card: updatedCard, positionsAhead: position)
            consecutiveFailures += 1
        } else if updatedCard.state == .learning || updatedCard.state == .relearning {
            let positions = rating == .hard ? 5 : 8
            queue = StudyQueue.reinsertCard(queue, card: updatedCard, positionsAhead: positions)
            consecutiveFailures = 0
        } else {
            queue = StudyQueue.removeCard(queue, cardId: updatedCard.id)
            consecutiveFailures = 0
        }

        isRevealed = false
        Task {
            await persistReview(updatedCard)
        }
    }

    private func startAgain() {
        queue = StudyQueue.buildQueue(cards)
        if queue.isEmpty {
            queue = StudyQueue.addExtraReviews(queue, cards: cards, count: cards.count)
        }
        isRevealed = false
        consecutiveFailures = 0
    }

    @MainActor
    private func updateAddCardAvailability() {
        isAddCardEnabled = !(isLoading || isSavingCard)
    }

    @MainActor
    private func addCard(chinese: String, pinyin: String, english: String) async -> Bool {
        guard !isSavingCard else { return false }

        addCardError = nil

        let normalizedChinese = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPinyin = pinyin.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedChinese.isEmpty,
              !normalizedPinyin.isEmpty,
              !normalizedEnglish.isEmpty else {
            return false
        }

        let newPhraseKey = FlashcardSeed.buildPhraseKey(
            chinese: normalizedChinese,
            pinyin: normalizedPinyin,
            english: normalizedEnglish
        )
        if cards.contains(where: {
            FlashcardSeed.buildPhraseKey(
                chinese: $0.chinese,
                pinyin: $0.pinyin,
                english: $0.english
            ) == newPhraseKey
        }) {
            addCardError = "This card already exists."
            return false
        }

        isSavingCard = true
        defer { isSavingCard = false }

        let newCard = Flashcard.newCard(
            chinese: normalizedChinese,
            pinyin: normalizedPinyin,
            english: normalizedEnglish
        )
        let previousCards = cards
        let previousQueue = queue
        let updatedCards = cards + [newCard]

        cards = updatedCards
        queue = StudyQueue.buildQueue(updatedCards)

        if let userId = authManager.user?.id {
            do {
                try await repository.insert(cards: [newCard], userId: userId)
            } catch {
                addCardError = "Could not save this card. Please try again."
                cards = previousCards
                queue = previousQueue
                return false
            }
        } else {
            LocalFlashcardStore.save(updatedCards)
        }

        return true
    }
}

#Preview {
    StudyView(isAddCardPresented: .constant(false), isAddCardEnabled: .constant(true))
        .environmentObject(AuthManager.shared)
}
