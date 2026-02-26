import Foundation

struct FlashcardSeed: Hashable {
    let chinese: String
    let pinyin: String
    let english: String
    let example: String?
    let examplePinyin: String?
    let exampleEnglish: String?

    init(
        chinese: String,
        pinyin: String,
        english: String,
        example: String? = nil,
        examplePinyin: String? = nil,
        exampleEnglish: String? = nil
    ) {
        self.chinese = chinese
        self.pinyin = pinyin
        self.english = english
        self.example = example
        self.examplePinyin = examplePinyin
        self.exampleEnglish = exampleEnglish
    }

    static func buildPhraseKey(chinese: String, pinyin: String, english: String) -> String {
        let normalizedChinese = chinese.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let normalizedPinyin = pinyin.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        let normalizedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        return "\(normalizedChinese)|\(normalizedPinyin)|\(normalizedEnglish)"
    }

    static func from(_ word: HSKWord) -> FlashcardSeed {
        FlashcardSeed(
            chinese: word.chinese,
            pinyin: word.pinyin,
            english: word.english
        )
    }
}
