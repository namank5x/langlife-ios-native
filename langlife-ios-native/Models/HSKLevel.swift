import Foundation

enum HSKLevel: Int, CaseIterable, Codable {
    case hsk1 = 1
    case hsk2 = 2

    var displayName: String {
        switch self {
        case .hsk1: return "HSK 1"
        case .hsk2: return "HSK 2"
        }
    }

    var cumulativeWordCount: Int {
        switch self {
        case .hsk1: return 300
        case .hsk2: return 500
        }
    }

    var description: String {
        switch self {
        case .hsk1: return "Basics — greetings, numbers, everyday words"
        case .hsk2: return "Elementary — travel, shopping, simple conversations"
        }
    }

    var levelWordCount: Int {
        switch self {
        case .hsk1: return 300
        case .hsk2: return 200
        }
    }
}
