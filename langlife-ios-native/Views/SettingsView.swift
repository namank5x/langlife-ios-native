import Auth
import GoogleSignIn
import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Binding var signInPresenter: UIViewController?

    @State private var localSignInPresenter: UIViewController?
    @State private var isSigningIn = false
    @State private var isSignInOptionsPresented = false
    @State private var pendingSignInProvider: SignInProvider?
    @State private var shouldStartSignIn = false
    @State private var errorMessage: String?
    @State private var signInAttemptID = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = authManager.user {
                        Text(user.email ?? "Signed in")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Sign out") {
                            Task {
                                await signOut()
                            }
                        }
                    } else {
                        Button {
                            isSignInOptionsPresented = true
                        } label: {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .foregroundStyle(AppColors.onAccent)
                                .background(Capsule().fill(AppColors.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSigningIn)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .background(
                SignInPresenter(presenter: $localSignInPresenter)
                    .allowsHitTesting(false)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
            )
            .sheet(
                isPresented: $isSignInOptionsPresented,
                onDismiss: {
                    shouldStartSignIn = pendingSignInProvider != nil
                    startPendingSignInIfPossible()
                },
                content: {
                SignInOptionsSheet(
                    onSelect: { provider in
                        pendingSignInProvider = provider
                        isSignInOptionsPresented = false
                    }
                )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
            )
            .onChange(of: scenePhase) { _ in
                startPendingSignInIfPossible()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func signInWithApple() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            try await authManager.signInWithApple()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func signOut() async {
        errorMessage = nil
        do {
            try await authManager.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        signInAttemptID += 1
        let attemptID = signInAttemptID

        Task.detached { [attemptID] in
            try await Task.sleep(nanoseconds: 12_000_000_000)
            await MainActor.run {
                guard isSigningIn, signInAttemptID == attemptID else { return }
                isSigningIn = false
                errorMessage = "Google sign-in did not start. Please try again."
            }
        }

        do {
            let presenter = signInPresenter ?? localSignInPresenter
            try await authManager.signInWithGoogle(presentingViewController: presenter)
            isSigningIn = false
        } catch {
            isSigningIn = false
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

#Preview {
    SettingsView(signInPresenter: .constant(nil))
        .environmentObject(AuthManager.shared)
}
