import Foundation

extension Error {
    var diagnosticDescription: String {
        if let decodingError = self as? DecodingError {
            switch decodingError {
            case .typeMismatch(let type, let context):
                return "Type mismatch for \(String(describing: type)): \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                return "Value not found for \(String(describing: type)): \(context.debugDescription)"
            case .keyNotFound(let key, let context):
                return "Key '\(key.stringValue)' not found: \(context.debugDescription)"
            case .dataCorrupted(let context):
                return "Data corrupted: \(context.debugDescription)"
            @unknown default:
                return "Decoding error."
            }
        }

        let nsError = self as NSError
        let domain = nsError.domain
        let code = nsError.code
        let description = nsError.localizedDescription
        return "\(domain) (\(code)): \(description)"
    }
}
