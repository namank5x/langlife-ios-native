import Foundation

enum SupabaseConfig {
    private static var didLogSupabaseURL = false

    static subscript(key: String) -> String? {
        if let value = Bundle.main.infoDictionary?[key] as? String, !value.isEmpty {
            logSupabaseURLIfNeeded(key: key, value: value)
            return value
        }

        guard let plistFileURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let plistData = try? Data(contentsOf: plistFileURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
                as? [String: Any]
        else { return nil }

        let value = plist[key] as? String
        if let value {
            logSupabaseURLIfNeeded(key: key, value: value)
        }
        return value
    }

    private static func logSupabaseURLIfNeeded(key: String, value: String) {
        guard key == "SUPABASE_URL", !didLogSupabaseURL else { return }
        didLogSupabaseURL = true
        print("SupabaseConfig SUPABASE_URL=\(value)")
    }
}
