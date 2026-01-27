import Foundation

enum SupabaseConfig {
    private static var didLogSupabaseURL = false

    static subscript(key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            return nil
        }
        logSupabaseURLIfNeeded(key: key, value: value)
        return value
    }

    private static func logSupabaseURLIfNeeded(key: String, value: String) {
        guard key == "SUPABASE_URL", !didLogSupabaseURL else { return }
        didLogSupabaseURL = true
        print("SupabaseConfig SUPABASE_URL=\(value)")
    }
}
