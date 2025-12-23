import Foundation

enum AppConfig {
    static var supabaseURL: URL {
        guard let value = SupabaseConfig["SUPABASE_URL"],
              let url = URL(string: value)
        else {
            preconditionFailure("Missing SUPABASE_URL in Supabase.plist")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let value = SupabaseConfig["SUPABASE_ANON_KEY"], !value.isEmpty else {
            preconditionFailure("Missing SUPABASE_ANON_KEY in Supabase.plist")
        }
        return value
    }

    static var apiBaseURL: URL {
        guard let value = SupabaseConfig["API_BASE_URL"],
              let url = URL(string: value)
        else {
            preconditionFailure("Missing API_BASE_URL in Supabase.plist")
        }
        return url
    }

    static var googleClientID: String {
        guard let value = SupabaseConfig["GOOGLE_IOS_CLIENT_ID"], !value.isEmpty else {
            preconditionFailure("Missing GOOGLE_IOS_CLIENT_ID in Supabase.plist")
        }
        return value
    }

    static var googleServerClientID: String? {
        guard let value = SupabaseConfig["GOOGLE_SERVER_CLIENT_ID"], !value.isEmpty else {
            return nil
        }
        return value
    }
}
