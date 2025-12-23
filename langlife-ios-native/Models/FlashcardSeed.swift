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

    static let defaults: [FlashcardSeed] = [
        FlashcardSeed(chinese: "你好", pinyin: "nǐ hǎo", english: "Hello"),
        FlashcardSeed(chinese: "謝謝", pinyin: "xiè xiè", english: "Thank you"),
        FlashcardSeed(chinese: "不客氣", pinyin: "bù kè qì", english: "You're welcome"),
        FlashcardSeed(chinese: "再見", pinyin: "zài jiàn", english: "Goodbye"),
        FlashcardSeed(chinese: "早安", pinyin: "zǎo ān", english: "Good morning"),
        FlashcardSeed(chinese: "晚安", pinyin: "wǎn ān", english: "Good night"),
        FlashcardSeed(chinese: "對不起", pinyin: "duì bù qǐ", english: "Sorry"),
        FlashcardSeed(chinese: "沒關係", pinyin: "méi guān xi", english: "It's okay / No problem"),
        FlashcardSeed(chinese: "請問", pinyin: "qǐng wèn", english: "Excuse me (to ask)"),
        FlashcardSeed(chinese: "多少錢？", pinyin: "duō shǎo qián?", english: "How much?"),
        FlashcardSeed(chinese: "好吃", pinyin: "hǎo chī", english: "Delicious"),
        FlashcardSeed(chinese: "珍珠奶茶", pinyin: "zhēn zhū nǎi chá", english: "Bubble tea"),
        FlashcardSeed(chinese: "小籠包", pinyin: "xiǎo lóng bāo", english: "Soup dumplings"),
        FlashcardSeed(chinese: "滷肉飯", pinyin: "lǔ ròu fàn", english: "Braised pork rice"),
        FlashcardSeed(chinese: "臭豆腐", pinyin: "chòu dòu fu", english: "Stinky tofu"),
        FlashcardSeed(chinese: "這個", pinyin: "zhè ge", english: "This one"),
        FlashcardSeed(chinese: "那個", pinyin: "nà ge", english: "That one"),
        FlashcardSeed(chinese: "要", pinyin: "yào", english: "Want / Need"),
        FlashcardSeed(chinese: "不要", pinyin: "bù yào", english: "Don't want"),
        FlashcardSeed(chinese: "可以", pinyin: "kě yǐ", english: "Can / May"),
        FlashcardSeed(chinese: "一", pinyin: "yī", english: "One (1)"),
        FlashcardSeed(chinese: "二", pinyin: "èr", english: "Two (2)"),
        FlashcardSeed(chinese: "三", pinyin: "sān", english: "Three (3)"),
        FlashcardSeed(chinese: "十", pinyin: "shí", english: "Ten (10)"),
        FlashcardSeed(chinese: "百", pinyin: "bǎi", english: "Hundred (100)"),
        FlashcardSeed(chinese: "捷運", pinyin: "jié yùn", english: "MRT / Metro"),
        FlashcardSeed(chinese: "悠遊卡", pinyin: "yōu yóu kǎ", english: "EasyCard (transit card)"),
        FlashcardSeed(chinese: "夜市", pinyin: "yè shì", english: "Night market"),
        FlashcardSeed(chinese: "便利商店", pinyin: "biàn lì shāng diàn", english: "Convenience store"),
        FlashcardSeed(chinese: "台北", pinyin: "Tái běi", english: "Taipei")
    ]
}
