import Foundation
import Translation

@available(iOS 18.0, *)
enum TranslationServiceError: LocalizedError {
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .emptyResult:
            return "Translation returned no results."
        }
    }
}

@available(iOS 18.0, *)
struct TranslationService {
    static func translateEnglishToTraditionalChinese(
        _ text: String,
        session: TranslationSession
    ) async throws -> String {
        let response = try await session.translate(text)
        let translated = response.targetText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationServiceError.emptyResult }
        return translated
    }

    static func translateTraditionalChineseToEnglish(
        _ text: String,
        session: TranslationSession
    ) async throws -> String {
        let response = try await session.translate(text)
        let translated = response.targetText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationServiceError.emptyResult }
        return translated
    }
}
