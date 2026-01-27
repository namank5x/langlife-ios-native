import Foundation

extension String {
    var pinyinTranscription: String {
        let transformed = applyingTransform(.toLatin, reverse: false) ?? ""
        let cleaned = transformed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
