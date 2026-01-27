import SwiftUI
import UIKit
import AuthenticationServices

struct LoginGateView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("guestModeEnabled") private var guestModeEnabled = false
    @Binding var signInPresenter: UIViewController?
    let onSkip: (() -> Void)?

    @State private var localSignInPresenter: UIViewController?
    @State private var isOnboardingPresented = false
    @State private var pendingSignInProvider: SignInProvider?
    @State private var shouldStartSignIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            OnboardingBackground()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    VStack(spacing: 12) {
                        Text("Sign in to continue")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text("Your scenes, flashcards, and progress stay synced across devices.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 520)

                    VStack(spacing: 12) {
                        FeatureRow(icon: "sparkles", title: "AI immersion scenes")
                        FeatureRow(icon: "mic.fill", title: "Speaking practice with feedback")
                        FeatureRow(icon: "rectangle.stack.fill", title: "Auto-made flashcards")
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
                    )
                    .frame(maxWidth: 520)

                    SignInOptionsView(
                        onSelect: { provider in
                            pendingSignInProvider = provider
                            shouldStartSignIn = true
                            startPendingSignInIfPossible()
                        },
                        title: nil
                    )
                    .disabled(isSigningIn)

                    Button("How it works") {
                        isOnboardingPresented = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let message = currentErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(
            SignInPresenter(presenter: $localSignInPresenter)
                .allowsHitTesting(false)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        )
        .fullScreenCover(isPresented: $isOnboardingPresented) {
            OnboardingView {
                isOnboardingPresented = false
            }
        }
        .onChange(of: scenePhase) { _ in
            startPendingSignInIfPossible()
        }
        .overlay(
            AuthStatusOverlay(
                status: authManager.authStatus,
                onCancel: {
                    Task {
                        try? await authManager.signOut()
                    }
                },
                onDismissError: {
                    authManager.resetAuthStatus()
                }
            )
        )
        .overlay(alignment: .topTrailing) {
            if !isSigningIn {
                Button("Skip") {
                    guestModeEnabled = true
                    errorMessage = nil
                    authManager.resetAuthStatus()
                    onSkip?()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(.opacity)
            }
        }
    }

    private var isSigningIn: Bool {
        if case .signingIn = authManager.authStatus {
            return true
        }
        return false
    }

    private var currentErrorMessage: String? {
        if case .error(let message) = authManager.authStatus {
            return message
        }
        return errorMessage
    }

    @MainActor
    private func signInWithApple() async {
        guard !isSigningIn else { return }
        errorMessage = nil

        do {
            try await authManager.signInWithApple()
        } catch {
            if isAppleSignInCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        guard !isSigningIn else { return }
        errorMessage = nil

        do {
            let presenter = signInPresenter ?? localSignInPresenter
            try await authManager.signInWithGoogle(presentingViewController: presenter)
        } catch {
            if isGoogleSignInCancelled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func isGoogleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.GIDSignIn"
            && nsError.code == -5
    }

    private func isAppleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }

    private func performSignIn(_ provider: SignInProvider) async {
        switch provider {
        case .apple:
            await signInWithApple()
        case .google:
            await signInWithGoogle()
        }
    }

    private func startPendingSignInIfPossible() {
        guard shouldStartSignIn, scenePhase == .active,
              let provider = pendingSignInProvider else { return }
        shouldStartSignIn = false
        Task { @MainActor in
            await Task.yield()
            await waitForStablePresentation()
            defer { pendingSignInProvider = nil }
            await performSignIn(provider)
        }
    }

    @MainActor
    private func waitForStablePresentation() async {
        for _ in 0..<30 {
            guard scenePhase == .active else {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }

            if let presenter = signInPresenter ?? localSignInPresenter {
                let root = presenter.view.window?.rootViewController ?? presenter
                let top = topViewController(from: root)
                if top.view.window != nil,
                   !top.isBeingPresented,
                   !top.isBeingDismissed {
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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

private struct FeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 28)
                .foregroundStyle(AppColors.accent)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Spacer()
        }
    }
}
