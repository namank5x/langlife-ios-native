import Foundation

enum AppConfig {
    static var supabaseURL: URL {
        validatedURL(for: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        guard let value = SupabaseConfig["SUPABASE_ANON_KEY"], !value.isEmpty else {
            preconditionFailure("Missing SUPABASE_ANON_KEY in app configuration")
        }
        return value
    }

    static var apiBaseURL: URL {
        validatedURL(for: "API_BASE_URL")
    }

    static var googleClientID: String {
        guard let value = SupabaseConfig["GOOGLE_IOS_CLIENT_ID"], !value.isEmpty else {
            preconditionFailure("Missing GOOGLE_IOS_CLIENT_ID in app configuration")
        }
        return value
    }

    static var googleServerClientID: String? {
        guard let value = SupabaseConfig["GOOGLE_SERVER_CLIENT_ID"], !value.isEmpty else {
            return nil
        }
        return value
    }

    static var revenueCatAPIKey: String {
        guard let value = SupabaseConfig["REVENUECAT_API_KEY"], !value.isEmpty else {
            preconditionFailure("Missing REVENUECAT_API_KEY in app configuration")
        }
        return value
    }

    static var supportEmail: String {
        guard let value = SupabaseConfig["SUPPORT_EMAIL"], !value.isEmpty else {
            preconditionFailure("Missing SUPPORT_EMAIL in app configuration")
        }
        return value
    }

    static var privacyPolicyURL: URL? {
        guard let value = SupabaseConfig["PRIVACY_POLICY_URL"], !value.isEmpty else {
            return nil
        }
        return validatedURL(from: value, key: "PRIVACY_POLICY_URL")
    }

    static var termsOfServiceURL: URL? {
        guard let value = SupabaseConfig["TERMS_OF_SERVICE_URL"], !value.isEmpty else {
            return nil
        }
        return validatedURL(from: value, key: "TERMS_OF_SERVICE_URL")
    }

    static var hskInfoURL: URL? {
        guard let value = SupabaseConfig["HSK_INFO_URL"], !value.isEmpty else {
            return nil
        }
        return validatedURL(from: value, key: "HSK_INFO_URL")
    }

    private static func validatedURL(for key: String) -> URL {
        guard let value = SupabaseConfig[key], !value.isEmpty else {
            preconditionFailure("Missing \(key) in app configuration")
        }
        return validatedURL(from: value, key: key)
    }

    private static func validatedURL(from value: String, key: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid \(key) URL: \(value)")
        }
        guard let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty
        else {
            preconditionFailure("Invalid \(key) URL: \(value). Expected http(s)://host")
        }
        return url
    }
}
