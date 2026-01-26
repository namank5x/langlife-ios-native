import Auth
import AuthenticationServices
import GoogleSignIn
import MessageUI
import RevenueCat
import SafariServices
import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Binding var signInPresenter: UIViewController?

    @State private var localSignInPresenter: UIViewController?
    @State private var isSignInOptionsPresented = false
    @State private var pendingSignInProvider: SignInProvider?
    @State private var shouldStartSignIn = false
    @State private var errorMessage: String?
    @State private var isPaywallPresented = false
    @State private var pendingPaywallPresentation = false
    @State private var supportMailDraft: SupportMailDraft?
    @State private var supportErrorMessage: String?
    @State private var isOnboardingPresented = false
    @State private var isDeleteAccountDialogPresented = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var isPrivacyPolicyPresented = false
    @State private var isTermsOfServicePresented = false
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    private let accountDeletionRepository = AccountDeletionRepository()
    private var manageSubscriptionURL: URL? {
        guard subscriptionManager.isPro else { return nil }
        return subscriptionManager.customerInfo?.managementURL
            ?? URL(string: "https://apps.apple.com/account/subscriptions")
    }
    private var signInOptionsSheet: some View {
        SignInOptionsSheet(
            onSelect: { provider in
                pendingSignInProvider = provider
                isSignInOptionsPresented = false
            }
        )
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private struct SupportMailDraft: Identifiable {
        let id = UUID()
        let subject: String
        let recipients: [String]
        let body: String
    }

    private struct SafariView: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> SFSafariViewController {
            SFSafariViewController(url: url)
        }

        func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    }

    @ViewBuilder
    private var accountSection: some View {
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
                .disabled(isDeletingAccount)
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

            if let message = currentErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
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

    private var supportSection: some View {
        Section("Support") {
            Button("Contact Support") {
                contactSupport()
            }

            Button("How it works") {
                isOnboardingPresented = true
            }

            if let supportErrorMessage {
                Text(supportErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var privacyPolicySection: some View {
        let privacyURL = AppConfig.privacyPolicyURL
        let termsURL = AppConfig.termsOfServiceURL
        if privacyURL != nil || termsURL != nil {
            Section("Legal") {
                if privacyURL != nil {
                    Button("Privacy Policy") {
                        isPrivacyPolicyPresented = true
                    }
                }

                if termsURL != nil {
                    Button("Terms of Use") {
                        isTermsOfServicePresented = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deleteAccountSection: some View {
        if authManager.user != nil {
            Section {
                Button(role: .destructive) {
                    deleteAccountErrorMessage = nil
                    isDeleteAccountDialogPresented = true
                } label: {
                    if isDeletingAccount {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Deleting...")
                        }
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(isDeletingAccount)
                if let deleteAccountErrorMessage {
                    Text(deleteAccountErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Danger")
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                subscriptionSection
                supportSection
                privacyPolicySection
                deleteAccountSection
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
                    signInOptionsSheet
            }
            )
            .fullScreenCover(isPresented: $isPaywallPresented) {
                PaywallScreen()
            }
            .sheet(isPresented: $isPrivacyPolicyPresented) {
                if let privacyURL = AppConfig.privacyPolicyURL {
                    SafariView(url: privacyURL)
                }
            }
            .sheet(isPresented: $isTermsOfServicePresented) {
                if let termsURL = AppConfig.termsOfServiceURL {
                    SafariView(url: termsURL)
                }
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingView {
                    isOnboardingPresented = false
                }
            }
            .sheet(item: $supportMailDraft) { draft in
                MailComposeView(
                    subject: draft.subject,
                    recipients: draft.recipients,
                    body: draft.body
                ) { result in
                    supportMailDraft = nil
                    switch result {
                    case .success(let composeResult):
                        if composeResult == .failed {
                            supportErrorMessage = "Mail could not be sent."
                        }
                    case .failure(let error):
                        supportErrorMessage = error.localizedDescription
                    }
                }
            }
            .onChange(of: scenePhase) { _, _ in
                startPendingSignInIfPossible()
            }
            .onChange(of: authManager.user?.id) { _, _ in
                handlePendingPaywallIfNeeded()
            }
            .task {
                await subscriptionManager.refresh(fetchPolicy: .fetchCurrent)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete account?",
                isPresented: $isDeleteAccountDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
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
                pendingPaywallPresentation = false
                return
            }
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
    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        guard let userId = authManager.user?.id else { return }
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        errorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await accountDeletionRepository.deleteAccount()
            LocalUserDataStore.clearAll(userId: userId)
            try? await authManager.signOut()
            dismiss()
        } catch {
            deleteAccountErrorMessage = deleteAccountErrorMessage(for: error)
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
                pendingPaywallPresentation = false
                return
            }
            errorMessage = error.localizedDescription
            pendingPaywallPresentation = false
        }
    }

    private func isAppleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }

    private func isGoogleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.GIDSignIn"
            && nsError.code == -5
    }

    private func deleteAccountErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIClientError,
           case APIClientError.httpError(let statusCode) = apiError,
           statusCode == 401 {
            return "Session expired. Please sign in again."
        }

        return "Unable to delete your account right now."
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

    private func contactSupport() {
        supportErrorMessage = nil
        let userId = authManager.user?.id.uuidString
        let userEmail = authManager.user?.email
        let subject = "Lang Life Support"
        let body = supportEmailBody(userId: userId, userEmail: userEmail)

        if MFMailComposeViewController.canSendMail() {
            supportMailDraft = SupportMailDraft(
                subject: subject,
                recipients: [AppConfig.supportEmail],
                body: body
            )
        } else {
            openSupportMailto(subject: subject, body: body)
        }
    }

    private func supportEmailBody(userId: String?, userEmail: String?) -> String {
        [
            "Please describe the issue or request.",
            "",
            "User ID: \(userId ?? "unknown")",
            "User Email: \(userEmail ?? "unknown")"
        ].joined(separator: "\n")
    }

    private func openSupportMailto(subject: String, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppConfig.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        guard let url = components.url else {
            supportErrorMessage = "Unable to build a support email."
            return
        }

        openURL(url) { accepted in
            if !accepted {
                supportErrorMessage = "Unable to open Mail."
            }
        }
    }

}

#Preview {
    SettingsView(signInPresenter: .constant(nil))
        .environmentObject(AuthManager.shared)
        .environmentObject(SubscriptionManager.shared)
}
