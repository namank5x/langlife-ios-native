import Auth
import GoogleSignIn
import RevenueCat
import RevenueCatUI
import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Binding var signInPresenter: UIViewController?

    @State private var localSignInPresenter: UIViewController?
    @State private var isSigningIn = false
    @State private var isSignInOptionsPresented = false
    @State private var pendingSignInProvider: SignInProvider?
    @State private var shouldStartSignIn = false
    @State private var errorMessage: String?
    @State private var isPaywallPresented = false
    @State private var pendingPaywallPresentation = false
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    private var manageSubscriptionURL: URL? {
        subscriptionManager.customerInfo?.managementURL
            ?? URL(string: "https://apps.apple.com/account/subscriptions")
    }
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

                if authManager.user != nil {
                    Section("Subscription") {
                        HStack {
                            Text("Lang Life Pro")
                            Spacer()
                            Text(subscriptionManager.isPro ? "Active" : "Not active")
                                .font(.subheadline)
                                .foregroundStyle(subscriptionManager.isPro ? .green : .secondary)
                        }

                        if subscriptionManager.isPro, let planLabel = subscriptionManager.activePlanLabel {
                            HStack {
                                Text("Plan")
                                Spacer()
                                Text(planLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if subscriptionManager.isPro,
                           let expiration = subscriptionManager.activePlanExpiration {
                            HStack {
                                Text("Renews on")
                                Spacer()
                                Text(dateFormatter.string(from: expiration))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !subscriptionManager.isPro {
                            Button("Buy Pro") {
                                presentPaywall()
                            }
                        }

                        if let managementURL = manageSubscriptionURL {
                            Link("Manage in App Store", destination: managementURL)
                        }

                        Button("Restore Purchases") {
                            Task {
                                await subscriptionManager.restore()
                            }
                        }

                        if let subscriptionError = subscriptionManager.lastErrorMessage {
                            Text(subscriptionError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
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
                    if pendingSignInProvider == nil {
                        pendingPaywallPresentation = false
                    }
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
            .sheet(isPresented: $isPaywallPresented) {
                PaywallView()
            }
            .onChange(of: scenePhase) { _ in
                startPendingSignInIfPossible()
            }
            .onChange(of: authManager.user?.id) { _, _ in
                handlePendingPaywallIfNeeded()
            }
            .task {
                await subscriptionManager.refresh()
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
            pendingPaywallPresentation = false
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

        do {
            let presenter = signInPresenter ?? localSignInPresenter
            try await authManager.signInWithGoogle(presentingViewController: presenter)
            isSigningIn = false
        } catch {
            isSigningIn = false
            if isGoogleSignInCancelled(error) {
                pendingPaywallPresentation = false
                return
            }
            errorMessage = error.localizedDescription
            pendingPaywallPresentation = false
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

    private func presentPaywall() {
        guard authManager.user == nil else {
            isPaywallPresented = true
            return
        }
        pendingPaywallPresentation = true
        isSignInOptionsPresented = true
    }

    private func handlePendingPaywallIfNeeded() {
        guard pendingPaywallPresentation, authManager.user != nil else { return }
        pendingPaywallPresentation = false
        isPaywallPresented = true
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
        .environmentObject(SubscriptionManager.shared)
}
