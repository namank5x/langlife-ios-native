import Auth
import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import GoogleSignIn
import Supabase
import Security
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var session: Session?
    @Published private(set) var user: User?
    @Published private(set) var authPhase: AuthPhase = .checking
    @Published private(set) var authStatus: AuthStatus = .idle

    private var authStateTask: Task<Void, Never>?
    private var appleSignInCoordinator: AppleSignInCoordinator?
    private var authStatusTimeoutTask: Task<Void, Never>?

    var isAuthenticated: Bool {
        session != nil
    }

    var accessToken: String? {
        session?.accessToken
    }

    private init() {
        authStateTask = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                if [.initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated].contains(event) {
                    self.session = session
                    self.user = session?.user
                    self.authPhase = session == nil ? .signedOut : .signedIn
                    self.handleAuthStateChange(event: event, session: session)
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws {
        guard
            let identityToken = credential.identityToken,
            let idToken = String(data: identityToken, encoding: .utf8)
        else {
            throw AuthManagerError.invalidIdentityToken
        }

        _ = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )

        if let fullName = credential.fullName?.formatted() {
            _ = try? await supabase.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
        }
    }

    func signInWithApple() async throws {
        beginSignIn(provider: .apple)
        do {
            let window = try activeWindow()
            let coordinator = AppleSignInCoordinator(window: window)
            appleSignInCoordinator = coordinator
            defer { appleSignInCoordinator = nil }

            let result = try await coordinator.start()
            try await signInWithApple(credential: result.credential, rawNonce: result.rawNonce)
        } catch {
            handleSignInError(error)
            throw error
        }
    }

    func signInWithGoogle(presentingViewController: UIViewController? = nil) async throws {
        beginSignIn(provider: .google)
        do {
            let configuration = GIDConfiguration(
                clientID: AppConfig.googleClientID,
                serverClientID: AppConfig.googleServerClientID
            )
            GIDSignIn.sharedInstance.configuration = configuration

            let presentingViewController = try await resolvePresentingViewController(
                fallback: presentingViewController
            )
            let result: GIDSignInResult
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthManagerError.invalidGoogleIdentityToken
            }
            let accessToken = result.user.accessToken.tokenString
            guard !accessToken.isEmpty else {
                throw AuthManagerError.invalidGoogleAccessToken
            }

            _ = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )
        } catch {
            handleSignInError(error)
            throw error
        }
    }

    func signOut() async throws {
        clearAuthStatus()
        try await supabase.auth.signOut()
    }

    func resetAuthStatus() {
        clearAuthStatus()
    }

    private func beginSignIn(provider: SignInProvider) {
        authStatus = .signingIn(provider: provider, startedAt: Date())
        scheduleAuthStatusTimeout()
    }

    private func scheduleAuthStatusTimeout() {
        authStatusTimeoutTask?.cancel()
        authStatusTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard case .signingIn = authStatus else { return }
            authStatus = .error(message: "Still finishing sign-in. Please try again.")
        }
    }

    private func handleSignInError(_ error: Error) {
        authStatusTimeoutTask?.cancel()
        if isUserCancellation(error) {
            authStatus = .idle
            return
        }
        authStatus = .error(message: error.localizedDescription)
    }

    private func clearAuthStatus() {
        authStatusTimeoutTask?.cancel()
        authStatusTimeoutTask = nil
        authStatus = .idle
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        if nsError.domain == "com.google.GIDSignIn",
           nsError.code == -5 {
            return true
        }
        return false
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated:
            clearAuthStatus()
        case .signedOut:
            clearAuthStatus()
        case .initialSession:
            if session == nil {
                clearAuthStatus()
            }
        default:
            break
        }
    }

    private func activeWindow() throws -> UIWindow {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in
                scene.activationState == .foregroundActive
                    || scene.activationState == .foregroundInactive
            }

        guard let windowScene else {
            throw AuthManagerError.missingPresentingViewController
        }

        if let keyWindow = windowScene.keyWindow {
            return keyWindow
        }

        if let window = windowScene.windows.first {
            return window
        }

        throw AuthManagerError.missingPresentingViewController
    }

    private func resolvePresentingViewController(
        fallback: UIViewController?
    ) async throws -> UIViewController {
        if let fallback {
            for _ in 0..<10 {
                if let window = fallback.view.window,
                   let rootViewController = window.rootViewController {
                    let topViewController = topViewController(from: rootViewController)
                    if topViewController.view.window != nil,
                       !topViewController.isBeingDismissed,
                       !topViewController.isBeingPresented {
                        return topViewController
                    }
                }
                if fallback.view.window != nil,
                   !fallback.isBeingDismissed, !fallback.isBeingPresented {
                    return fallback
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        let window = try activeWindow()
        guard let rootViewController = window.rootViewController else {
            throw AuthManagerError.missingPresentingViewController
        }

        for _ in 0..<20 {
            let topViewController = topViewController(from: rootViewController)
            if let alertController = topViewController as? UIAlertController,
               let presentingViewController = alertController.presentingViewController,
               presentingViewController.view.window != nil,
               !presentingViewController.isBeingDismissed,
               !presentingViewController.isBeingPresented {
                return presentingViewController
            }
            if topViewController.view.window != nil,
               !topViewController.isBeingDismissed,
               !topViewController.isBeingPresented {
                return topViewController
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        throw AuthManagerError.missingPresentingViewController
    }

    private func topViewController(from rootViewController: UIViewController) -> UIViewController {
        var topViewController = rootViewController
        while true {
            if let presented = topViewController.presentedViewController {
                topViewController = presented
                continue
            }
            if let navigationController = topViewController as? UINavigationController,
               let visibleViewController = navigationController.visibleViewController {
                topViewController = visibleViewController
                continue
            }
            if let tabBarController = topViewController as? UITabBarController,
               let selectedViewController = tabBarController.selectedViewController {
                topViewController = selectedViewController
                continue
            }
            break
        }
        return topViewController
    }
}

enum AuthPhase: Equatable {
    case checking
    case signedOut
    case signedIn
}

enum AuthStatus: Equatable {
    case idle
    case signingIn(provider: SignInProvider, startedAt: Date)
    case error(message: String)
}

enum AuthManagerError: LocalizedError {
    case invalidIdentityToken
    case invalidAppleCredential
    case invalidAppleNonce
    case invalidGoogleIdentityToken
    case invalidGoogleAccessToken
    case missingPresentingViewController

    var errorDescription: String? {
        switch self {
        case .invalidIdentityToken:
            return "Unable to read the Apple identity token."
        case .invalidAppleCredential:
            return "Unexpected Apple credential."
        case .invalidAppleNonce:
            return "Unable to generate the Apple sign-in nonce."
        case .invalidGoogleIdentityToken:
            return "Unable to read the Google identity token."
        case .invalidGoogleAccessToken:
            return "Unable to read the Google access token."
        case .missingPresentingViewController:
            return "Unable to find a screen to present sign-in."
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let window: UIWindow
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var controller: ASAuthorizationController?
    private var rawNonce: String?

    init(window: UIWindow) {
        self.window = window
    }

    func start() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]
            do {
                let rawNonce = try Self.randomNonce()
                self.rawNonce = rawNonce
                request.nonce = Self.sha256(rawNonce)
            } catch {
                resume(with: .failure(error))
                return
            }

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            resume(with: .failure(AuthManagerError.invalidAppleCredential))
            return
        }
        guard let rawNonce else {
            resume(with: .failure(AuthManagerError.invalidAppleNonce))
            return
        }
        resume(with: .success(AppleSignInResult(credential: credential, rawNonce: rawNonce)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        resume(with: .failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }

    private func resume(with result: Result<AppleSignInResult, Error>) {
        guard let continuation else { return }
        continuation.resume(with: result)
        self.continuation = nil
        controller = nil
        rawNonce = nil
    }

    private static func randomNonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                throw AuthManagerError.invalidAppleNonce
            }

            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

private struct AppleSignInResult {
    let credential: ASAuthorizationAppleIDCredential
    let rawNonce: String
}
