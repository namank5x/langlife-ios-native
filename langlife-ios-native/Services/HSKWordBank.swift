import Foundation

struct HSKWord: Codable {
    let chinese: String
    let pinyin: String
    let english: String
    let level: Int
}

enum HSKWordBank {
    private static let allWords: [HSKWord] = {
        guard let url = Bundle.main.url(forResource: "hsk_words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode([HSKWord].self, from: data)
        else {
            return []
        }
        return words
    }()

    static func words(upTo level: HSKLevel) -> [HSKWord] {
        allWords.filter { $0.level <= level.rawValue }
    }

    static func words(at level: HSKLevel) -> [HSKWord] {
        allWords.filter { $0.level == level.rawValue }
    }
}
