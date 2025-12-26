import Auth
import SwiftUI

struct ManageCardsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var cardStore: FlashcardStore
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredCards: [Flashcard] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cardStore.cards }
        let query = trimmed.lowercased()
        return cardStore.cards.filter { card in
            card.english.lowercased().contains(query)
                || card.chinese.lowercased().contains(query)
                || card.pinyin.lowercased().contains(query)
        }
    }

    var body: some View {
        content
            .navigationTitle("Cards")
            .task {
                await cardStore.loadIfNeeded(for: authManager.user?.id)
            }
    }

    @ViewBuilder
    private var content: some View {
        if authManager.user == nil {
            VStack(spacing: 12) {
                Text("Sign in to manage your cards.")
                    .font(.headline)
                Text("Your cards are tied to your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else if cardStore.isLoading && cardStore.cards.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let errorMessage = cardStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(cardStore.isOfflineNotice ? Color.secondary : .red)
                    }
                }

                if filteredCards.isEmpty {
                    Section {
                        Text(isSearching ? "No matching cards." : "No cards yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(filteredCards) { card in
                        NavigationLink {
                            EditCardView(card: card)
                        } label: {
                            CardRow(card: card)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search cards")
            .refreshable {
                await cardStore.refresh(for: authManager.user?.id)
            }
        }
    }
}

private struct CardRow: View {
    let card: Flashcard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.english)
                .font(.headline)
            Text("\(card.chinese) / \(card.pinyin)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct EditCardView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var cardStore: FlashcardStore

    let card: Flashcard

    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        AddCardSheet(
            isSaving: isSaving,
            isDeleting: isDeleting,
            errorMessage: errorMessage,
            existingPhraseKeys: existingPhraseKeys,
            onSave: { chinese, pinyin, english in
                await updateCard(chinese: chinese, pinyin: pinyin, english: english)
            },
            onUpdate: {
                errorMessage = nil
            },
            onDelete: {
                await deleteCard()
            },
            mode: .edit,
            initialChinese: card.chinese,
            initialPinyin: card.pinyin,
            initialEnglish: card.english
        )
    }

    private var existingPhraseKeys: Set<String> {
        Set(
            cardStore.cards
                .filter { $0.id != card.id }
                .map {
                    FlashcardSeed.buildPhraseKey(
                        chinese: $0.chinese,
                        pinyin: $0.pinyin,
                        english: $0.english
                    )
                }
        )
    }

    @MainActor
    private func updateCard(
        chinese: String,
        pinyin: String,
        english: String
    ) async -> Bool {
        guard !isSaving else { return false }
        guard let userId = authManager.user?.id else {
            errorMessage = "Please sign in to edit cards."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await cardStore.updateContent(
                cardId: card.id,
                chinese: chinese,
                pinyin: pinyin,
                english: english,
                userId: userId
            )
            return true
        } catch {
            errorMessage = "Could not update this card. Please try again."
            return false
        }
    }

    @MainActor
    private func deleteCard() async -> Bool {
        guard !isDeleting else { return false }
        guard let userId = authManager.user?.id else {
            errorMessage = "Please sign in to delete cards."
            return false
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await cardStore.deleteCard(cardId: card.id, userId: userId)
            return true
        } catch {
            errorMessage = "Could not delete this card. Please try again."
            return false
        }
    }
}

#Preview {
    NavigationStack {
        ManageCardsView()
            .environmentObject(AuthManager.shared)
            .environmentObject(FlashcardStore())
    }
}
