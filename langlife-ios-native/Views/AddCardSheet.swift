import SwiftUI
import Translation
import _Translation_SwiftUI

struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isSaving: Bool
    let isDeleting: Bool
    let errorMessage: String?
    let existingPhraseKeys: Set<String>
    let onSave: (_ chinese: String, _ pinyin: String, _ english: String) async -> Bool
    let onUpdate: () -> Void
    let onDelete: (() async -> Bool)?
    let mode: Mode

    @State private var chinese = ""
    @State private var pinyin = ""
    @State private var english = ""
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var didManuallyEditTranslation = false
    @State private var isApplyingTranslation = false
    @State private var lastTranslatedEnglish = ""
    @State private var translationRequestID = UUID()
    @State private var translationTask: Task<Void, Never>?
    @State private var translationQueue = TranslationQueue()
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var focusedField: Field?

    enum Mode {
        case create
        case edit
    }

    init(
        isSaving: Bool,
        isDeleting: Bool = false,
        errorMessage: String?,
        existingPhraseKeys: Set<String>,
        onSave: @escaping (_ chinese: String, _ pinyin: String, _ english: String) async -> Bool,
        onUpdate: @escaping () -> Void,
        onDelete: (() async -> Bool)? = nil,
        mode: Mode = .create,
        initialChinese: String = "",
        initialPinyin: String = "",
        initialEnglish: String = ""
    ) {
        self.isSaving = isSaving
        self.isDeleting = isDeleting
        self.errorMessage = errorMessage
        self.existingPhraseKeys = existingPhraseKeys
        self.onSave = onSave
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.mode = mode
        _chinese = State(initialValue: initialChinese)
        _pinyin = State(initialValue: initialPinyin)
        _english = State(initialValue: initialEnglish)
    }

    private enum Field {
        case chinese
        case pinyin
        case english
    }

    private var trimmedChinese: String {
        chinese.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPinyin: String {
        pinyin.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEnglish: String {
        english.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        !trimmedChinese.isEmpty
            && !trimmedPinyin.isEmpty
            && !trimmedEnglish.isEmpty
            && !isTranslating
    }

    private var duplicateMessage: String? {
        guard !trimmedChinese.isEmpty,
              !trimmedPinyin.isEmpty,
              !trimmedEnglish.isEmpty else {
            return nil
        }

        let phraseKey = FlashcardSeed.buildPhraseKey(
            chinese: trimmedChinese,
            pinyin: trimmedPinyin,
            english: trimmedEnglish
        )
        return existingPhraseKeys.contains(phraseKey) ? "This card already exists." : nil
    }

    private var bannerMessage: String? {
        errorMessage ?? duplicateMessage
    }

    private var canSave: Bool {
        isFormValid && duplicateMessage == nil
    }

    private var navigationTitle: String {
        mode == .create ? "New Card" : "Edit Card"
    }

    private var actionTitle: String {
        mode == .create ? "Save" : "Update"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let bannerMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Text(bannerMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemRed).opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.systemRed).opacity(0.25), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("English")
                        .font(.headline)
                    TextField("Enter English", text: $english, axis: .vertical)
                        .font(.system(size: 26, weight: .semibold))
                        .focused($focusedField, equals: .english)
                        .submitLabel(.next)
                        .lineLimit(2, reservesSpace: true)
                        .padding(16)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )
                        .onSubmit {
                            scheduleTranslation(force: true)
                            focusedField = .chinese
                        }
                }

                if isTranslating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Translating...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let translationError {
                    Text(translationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if shouldShowRetranslate {
                    Button {
                        scheduleTranslation(force: true)
                    } label: {
                        Label("Re-translate", systemImage: "sparkles")
                            .font(.subheadline)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Pinyin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Pinyin", text: $pinyin, axis: .vertical)
                        .font(.system(size: 18, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .pinyin)
                        .submitLabel(.next)
                        .lineLimit(2, reservesSpace: true)
                        .padding(14)
                        .frame(minHeight: 64, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )
                        .onSubmit {
                            focusedField = .chinese
                        }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Chinese")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Chinese", text: $chinese, axis: .vertical)
                        .font(.system(size: 20, weight: .semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .chinese)
                        .submitLabel(.done)
                        .lineLimit(2, reservesSpace: true)
                        .padding(14)
                        .frame(minHeight: 72, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )
                        .onSubmit {
                            focusedField = nil
                        }
                }

                if mode == .edit, onDelete != nil {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isSaving || isDeleting)
                    .padding(.top, 8)
                }

            }
            .padding(20)
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if mode == .create {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(actionTitle) {
                    Task {
                        let success = await onSave(trimmedChinese, trimmedPinyin, trimmedEnglish)
                        if success {
                            dismiss()
                        }
                    }
                }
                .disabled(!canSave || isSaving || isDeleting)
            }
        }
        .confirmationDialog(
            "Delete Card?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let onDelete else { return }
                Task {
                    let success = await onDelete()
                    if success {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            focusedField = .english
        }
        .onDisappear {
            translationTask?.cancel()
            translationQueue.finish()
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: chinese) { _, _ in
            if !isApplyingTranslation, !trimmedEnglish.isEmpty {
                didManuallyEditTranslation = true
            }
            onUpdate()
        }
        .onChange(of: pinyin) { _, _ in
            if !isApplyingTranslation, !trimmedEnglish.isEmpty {
                didManuallyEditTranslation = true
            }
            onUpdate()
        }
        .onChange(of: english) { _, _ in
            didManuallyEditTranslation = false
            translationError = nil
            scheduleTranslation(force: false)
            onUpdate()
        }
        .translationTask(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hant")
        ) { session in
            await runTranslationLoop(using: session)
        }
    }

    private var shouldShowRetranslate: Bool {
        !trimmedEnglish.isEmpty && !isTranslating && (translationError != nil || didManuallyEditTranslation)
    }

    private func scheduleTranslation(force: Bool) {
        translationTask?.cancel()
        translationError = nil

        let englishText = trimmedEnglish
        guard !englishText.isEmpty else {
            isTranslating = false
            if !didManuallyEditTranslation {
                chinese = ""
                pinyin = ""
            }
            return
        }

        let requestID = UUID()
        translationRequestID = requestID

        translationTask = Task {
            if !force {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                translationQueue.send(
                    TranslationQueue.Request(
                        text: englishText,
                        requestID: requestID,
                        force: force
                    )
                )
            }
        }
    }

    @MainActor
    private func translate(
        english: String,
        requestID: UUID,
        force: Bool,
        session: TranslationSession
    ) async {
        guard requestID == translationRequestID else { return }
        if !force {
            guard !didManuallyEditTranslation else { return }
            guard english != lastTranslatedEnglish else { return }
        }

        isTranslating = true
        translationError = nil

        do {
            let translated = try await TranslationService.translateEnglishToTraditionalChinese(
                english,
                session: session
            )
            guard !Task.isCancelled, requestID == translationRequestID else {
                isTranslating = false
                return
            }
            if didManuallyEditTranslation && !force {
                isTranslating = false
                return
            }

            let pinyinText = generatePinyin(from: translated)
            isApplyingTranslation = true
            chinese = translated
            pinyin = pinyinText
            isApplyingTranslation = false
            lastTranslatedEnglish = english
            didManuallyEditTranslation = false
        } catch {
            if !Task.isCancelled {
                translationError = "Unable to translate right now."
            }
        }

        isTranslating = false
    }

    private func generatePinyin(from chineseText: String) -> String {
        let transformed = chineseText.applyingTransform(.toLatin, reverse: false) ?? ""
        let cleaned = transformed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    private func runTranslationLoop(using session: TranslationSession) async {
        for await request in translationQueue.stream {
            if Task.isCancelled { break }
            await translate(
                english: request.text,
                requestID: request.requestID,
                force: request.force,
                session: session
            )
        }
    }
}

private final class TranslationQueue {
    struct Request: Sendable {
        let text: String
        let requestID: UUID
        let force: Bool
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

#Preview {
    NavigationStack {
        AddCardSheet(
            isSaving: false,
            errorMessage: nil,
            existingPhraseKeys: [],
            onSave: { _, _, _ in
                await Task.yield()
                return true
            },
            onUpdate: {}
        )
    }
}
