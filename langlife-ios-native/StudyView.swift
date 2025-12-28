//
//  StudyView.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import Auth
import SwiftUI
import UIKit

struct StudyView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var cardStore: FlashcardStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @Binding var signInPresenter: UIViewController?
    @Binding var isAddCardPresented: Bool
    @Binding var isAddCardEnabled: Bool
    @Binding var isManageCardsPresented: Bool

    @State private var queue: [QueuedCard] = []
    @State private var isRevealed = false
    @State private var consecutiveFailures = 0
    @State private var reviewErrorMessage: String?
    @State private var isSavingCard = false
    @State private var addCardError: String?
    @State private var localSignInPresenter: UIViewController?
    @State private var isSigningIn = false
    @State private var isSignInOptionsPresented = false
    @State private var pendingSignInProvider: SignInProvider?
    @State private var shouldStartSignIn = false
    @State private var signInError: String?
    @State private var pendingRating: Rating?
    @State private var pendingCardId: UUID?
    @State private var pendingAddCard = false
    @State private var pendingManageCards = false
    @State private var cardsCountSnapshot = 0
    @State private var queueUserId: UUID?
    @State private var reviewActionCount = 0
    @State private var reviewActionDayStart: Date?
    @State private var isPaywallPresented = false

    @StateObject private var ttsService = TTSService()

    private let actionButtonHeight: CGFloat = 48

    private var currentCard: Flashcard? {
        queue.first?.card
    }

    private var shouldShowReviewActions: Bool {
        currentCard != nil && isRevealed
    }

    private var cards: [Flashcard] {
        cardStore.cards
    }

    private var existingPhraseKeys: Set<String> {
        Set(
            cardStore.cards.map {
                FlashcardSeed.buildPhraseKey(
                    chinese: $0.chinese,
                    pinyin: $0.pinyin,
                    english: $0.english
                )
            }
        )
    }

    private var combinedErrorMessage: String? {
        reviewErrorMessage ?? cardStore.errorMessage
    }

    private var combinedErrorIsOffline: Bool {
        if let reviewErrorMessage {
            return reviewErrorMessage == FlashcardStore.offlineMessage
        }
        return cardStore.isOfflineNotice
    }

    private var isReviewLimitReached: Bool {
        !subscriptionManager.isPro
            && reviewActionCount >= SubscriptionLimits.freeDailyReviewLimit
    }

    var body: some View {
        VStack {
            Spacer(minLength: 24)

            if cardStore.isLoading && cardStore.cards.isEmpty {
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
                    .disabled(cardStore.isLoading || ttsService.isLoading)

                    if shouldShowReviewActions {
                        HStack(spacing: 12) {
                            Button {
                                requestRating(.again)
                            } label: {
                                Text("Again")
                                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSigningIn)

                            Button {
                                // "Easy" maps to Good for a more conservative schedule.
                                requestRating(.good)
                            } label: {
                                Text("Easy")
                                    .frame(maxWidth: .infinity, minHeight: actionButtonHeight)
                            }
                            .neutralProminentButton()
                            .disabled(isSigningIn)
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

            if let combinedErrorMessage {
                Text(combinedErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(combinedErrorIsOffline ? Color.secondary : .red)
                    .padding(.top, 12)
            }

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .background(
            SignInPresenter(presenter: $localSignInPresenter)
                .allowsHitTesting(false)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        )
        .sheet(isPresented: $isAddCardPresented) {
            NavigationStack {
                AddCardSheet(
                    isSaving: isSavingCard,
                    errorMessage: addCardError,
                    existingPhraseKeys: existingPhraseKeys,
                    onSave: { chinese, pinyin, english in
                        await addCard(chinese: chinese, pinyin: pinyin, english: english)
                    },
                    onUpdate: {
                        addCardError = nil
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: $isSignInOptionsPresented,
            onDismiss: {
                if pendingSignInProvider == nil {
                    clearPendingActions()
                }
                shouldStartSignIn = pendingSignInProvider != nil
                startPendingSignInIfPossible()
            },
            content: {
                SignInOptionsSheet(
                    onSelect: { provider in
                        pendingSignInProvider = provider
                        isSignInOptionsPresented = false
                    }
                )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
        )
        .sheet(isPresented: $isPaywallPresented) {
            PaywallScreen()
        }
        .navigationDestination(isPresented: $isManageCardsPresented) {
            ManageCardsView()
        }
        .task {
            await loadCardIfNeeded()
            refreshDailyReviewCountIfNeeded()
        }
        .onAppear {
            updateAddCardAvailability()
            refreshDailyReviewCountIfNeeded()
        }
        .onChange(of: scenePhase) { _ in
            startPendingSignInIfPossible()
            if scenePhase == .active {
                refreshDailyReviewCountIfNeeded()
            }
        }
        .onChange(of: cardStore.isLoading) { _, _ in
            updateAddCardAvailability()
        }
        .onChange(of: isSavingCard) { _, _ in
            updateAddCardAvailability()
        }
        .onChange(of: isAddCardPresented) { _, newValue in
            if newValue {
                guard authManager.user != nil else {
                    setPendingAddCard()
                    isAddCardPresented = false
                    presentSignInOptions()
                    return
                }
                addCardError = nil
            }
        }
        .onChange(of: isManageCardsPresented) { _, newValue in
            if newValue {
                guard authManager.user != nil else {
                    setPendingManageCards()
                    isManageCardsPresented = false
                    presentSignInOptions()
                    return
                }
            }
        }
        .onChange(of: authManager.user?.id) { _, _ in
            Task {
                await loadCardIfNeeded()
                completePendingActionsIfNeeded()
            }
            if isAddCardPresented {
                addCardError = authManager.user == nil ? "Please sign in to add a card." : nil
            }
            reviewActionCount = 0
            reviewActionDayStart = nil
            refreshDailyReviewCountIfNeeded()
        }
        .onChange(of: cardStore.cards) { _, newValue in
            syncQueue(with: newValue)
        }
        .onChange(of: currentCard?.id) { _, _ in
            isRevealed = false
        }
    }

    @MainActor
    private func requestRating(_ rating: Rating) {
        guard !isSigningIn else { return }
        guard authManager.user != nil else {
            setPendingRating(rating)
            presentSignInOptions()
            return
        }
        if isLimitedRating(rating) {
            refreshDailyReviewCountIfNeeded()
            guard !isReviewLimitReached else {
                isPaywallPresented = true
                return
            }
        }
        handleRate(rating)
    }

    @MainActor
    private func completePendingActionsIfNeeded() {
        guard authManager.user != nil else { return }
        if let rating = pendingRating {
            guard let pendingCardId, pendingCardId == currentCard?.id else {
                clearPendingRating()
                return
            }
            clearPendingRating()
            requestRating(rating)
            return
        }

        if pendingAddCard {
            pendingAddCard = false
            isAddCardPresented = true
        }

        if pendingManageCards {
            pendingManageCards = false
            isManageCardsPresented = true
        }
    }

    private func clearPendingRating() {
        pendingRating = nil
        pendingCardId = nil
    }

    private func clearPendingActions() {
        clearPendingRating()
        pendingAddCard = false
        pendingManageCards = false
    }

    private func setPendingRating(_ rating: Rating) {
        pendingRating = rating
        pendingCardId = currentCard?.id
        pendingAddCard = false
    }

    private func setPendingAddCard() {
        pendingAddCard = true
        pendingManageCards = false
        clearPendingRating()
    }

    private func setPendingManageCards() {
        pendingManageCards = true
        pendingAddCard = false
        clearPendingRating()
    }

    private func presentSignInOptions() {
        guard !isSigningIn else { return }
        signInError = nil
        pendingSignInProvider = nil
        shouldStartSignIn = false
        isSignInOptionsPresented = true
    }

    @MainActor
    private func signInWithApple() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            try await authManager.signInWithApple()
        } catch {
            signInError = error.localizedDescription
            clearPendingActions()
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil

        do {
            let presenter = signInPresenter ?? localSignInPresenter
            try await authManager.signInWithGoogle(presentingViewController: presenter)
            isSigningIn = false
        } catch {
            isSigningIn = false
            if isGoogleSignInCancelled(error) {
                clearPendingActions()
                return
            }
            signInError = error.localizedDescription
            clearPendingActions()
        }
    }

    private func isGoogleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.GIDSignIn"
            && nsError.code == -5
    }

    private func performSignIn(_ provider: SignInProvider) async {
        switch provider {
        case .apple:
            await signInWithApple()
        case .google:
            await signInWithGoogle()
        }
    }

    private func startPendingSignInIfPossible() {
        guard shouldStartSignIn, scenePhase == .active,
              let provider = pendingSignInProvider else { return }
        shouldStartSignIn = false
        Task { @MainActor in
            await Task.yield()
            await waitForStablePresentation()
            defer { pendingSignInProvider = nil }
            await performSignIn(provider)
        }
    }

    @MainActor
    private func waitForStablePresentation() async {
        for _ in 0..<30 {
            guard scenePhase == .active else {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }

            if let presenter = signInPresenter ?? localSignInPresenter {
                let root = presenter.view.window?.rootViewController ?? presenter
                let top = topViewController(from: root)
                if top.view.window != nil,
                   !top.isBeingPresented,
                   !top.isBeingDismissed {
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func topViewController(from rootViewController: UIViewController) -> UIViewController {
        var topViewController = rootViewController
        while true {
            if let presented = topViewController.presentedViewController {
                topViewController = presented
                continue
            }
            if let navigationController = topViewController as? UINavigationController,
               let visibleViewController = navigationController.visibleViewController {
                topViewController = visibleViewController
                continue
            }
            if let tabBarController = topViewController as? UITabBarController,
               let selectedViewController = tabBarController.selectedViewController {
                topViewController = selectedViewController
                continue
            }
            break
        }
        return topViewController
    }

    @MainActor
    private func loadCardIfNeeded() async {
        await cardStore.loadIfNeeded(for: authManager.user?.id)
        if queueUserId != authManager.user?.id {
            rebuildQueue(from: cardStore.cards)
        } else if cardsCountSnapshot == 0 {
            rebuildQueue(from: cardStore.cards)
        } else {
            syncQueue(with: cardStore.cards)
        }
    }

    @MainActor
    private func persistReview(_ updatedCard: Flashcard) async {
        do {
            try await cardStore.persistReview(updatedCard, userId: authManager.user?.id)
        } catch {
            reviewErrorMessage = error.isOffline
                ? FlashcardStore.offlineMessage
                : "Could not save progress. Please try again."
        }
    }

    @MainActor
    private func rebuildQueue(from cards: [Flashcard]) {
        queue = StudyQueue.buildQueue(cards)
        isRevealed = false
        consecutiveFailures = 0
        cardsCountSnapshot = cards.count
        queueUserId = authManager.user?.id
    }

    @MainActor
    private func syncQueue(with cards: [Flashcard]) {
        if cards.count != cardsCountSnapshot {
            rebuildQueue(from: cards)
            return
        }

        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        queue = queue.compactMap { queued in
            guard let updatedCard = cardMap[queued.card.id] else { return nil }
            return QueuedCard(card: updatedCard, priority: queued.priority, category: queued.category)
        }
    }

    private func revealAnswerIfNeeded() {
        guard !isRevealed else { return }
        isRevealed = true
    }

    @MainActor
    private func handleRate(_ rating: Rating) {
        guard let card = currentCard else { return }

        let updatedCard = FSRS.reviewCard(card, rating: rating)
        cardStore.updateCard(updatedCard)

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
        reviewErrorMessage = nil
        if !subscriptionManager.isPro, isLimitedRating(rating), let userId = authManager.user?.id {
            let dayStart = Calendar.current.startOfDay(for: Date())
            reviewActionCount = LocalReviewLimitStore.incrementCount(
                userId: userId,
                dayStart: dayStart
            )
            reviewActionDayStart = dayStart
        }
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
        isAddCardEnabled = !(cardStore.isLoading || isSavingCard)
    }

    @MainActor
    private func addCard(chinese: String, pinyin: String, english: String) async -> Bool {
        guard !isSavingCard else { return false }
        guard authManager.user != nil else {
            addCardError = "Please sign in to add a card."
            return false
        }

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
        if existingPhraseKeys.contains(newPhraseKey) {
            addCardError = "This card already exists."
            return false
        }

        isSavingCard = true
        defer { isSavingCard = false }
        guard let userId = authManager.user?.id else { return false }
        do {
            _ = try await cardStore.addCard(
                chinese: normalizedChinese,
                pinyin: normalizedPinyin,
                english: normalizedEnglish,
                userId: userId
            )
            rebuildQueue(from: cardStore.cards)
            return true
        } catch {
            addCardError = "Could not save this card. Please try again."
            return false
        }
    }

    @MainActor
    private func refreshDailyReviewCountIfNeeded() {
        guard let userId = authManager.user?.id else {
            reviewActionCount = 0
            reviewActionDayStart = nil
            return
        }

        let dayStart = Calendar.current.startOfDay(for: Date())
        if reviewActionDayStart == dayStart { return }
        reviewActionCount = LocalReviewLimitStore.loadCount(userId: userId, dayStart: dayStart)
        reviewActionDayStart = dayStart
    }

    private func isLimitedRating(_ rating: Rating) -> Bool {
        rating == .again || rating == .good
    }
}

#Preview {
    StudyView(
        signInPresenter: .constant(nil),
        isAddCardPresented: .constant(false),
        isAddCardEnabled: .constant(true),
        isManageCardsPresented: .constant(false)
    )
        .environmentObject(AuthManager.shared)
        .environmentObject(FlashcardStore())
}
