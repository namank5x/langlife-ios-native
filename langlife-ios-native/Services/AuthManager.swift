import Auth
import AuthenticationServices
import Combine
import Foundation
import GoogleSignIn
import Supabase
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var session: Session?
    @Published private(set) var user: User?

    private var authStateTask: Task<Void, Never>?
    private var appleSignInCoordinator: AppleSignInCoordinator?

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
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard
            let identityToken = credential.identityToken,
            let idToken = String(data: identityToken, encoding: .utf8)
        else {
            throw AuthManagerError.invalidIdentityToken
        }

        _ = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken
            )
        )

        if let fullName = credential.fullName?.formatted() {
            _ = try? await supabase.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
        }
    }

    func signInWithApple() async throws {
        let window = try activeWindow()
        let coordinator = AppleSignInCoordinator(window: window)
        appleSignInCoordinator = coordinator
        defer { appleSignInCoordinator = nil }

        let credential = try await coordinator.start()
        try await signInWithApple(credential: credential)
    }

    func signInWithGoogle(presentingViewController: UIViewController? = nil) async throws {
        let configuration = GIDConfiguration(
            clientID: AppConfig.googleClientID,
            serverClientID: AppConfig.googleServerClientID
        )
        GIDSignIn.sharedInstance.configuration = configuration

        let presentingViewController = try await resolvePresentingViewController(
            fallback: presentingViewController
        )
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        } catch {
            throw error
        }

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
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
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

enum AuthManagerError: LocalizedError {
    case invalidIdentityToken
    case invalidAppleCredential
    case invalidGoogleIdentityToken
    case invalidGoogleAccessToken
    case missingPresentingViewController

    var errorDescription: String? {
        switch self {
        case .invalidIdentityToken:
            return "Unable to read the Apple identity token."
        case .invalidAppleCredential:
            return "Unexpected Apple credential."
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
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    init(window: UIWindow) {
        self.window = window
    }

    func start() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email, .fullName]

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
        resume(with: .success(credential))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        resume(with: .failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }

    private func resume(with result: Result<ASAuthorizationAppleIDCredential, Error>) {
        guard let continuation else { return }
        continuation.resume(with: result)
        self.continuation = nil
        controller = nil
    }
}
