import Auth
import MessageUI
import RevenueCat
import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var cardStore: FlashcardStore
    @AppStorage("hskLevel") private var hskLevel = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Binding var signInPresenter: UIViewController?

    @State private var isLoginGatePresented = false
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
    @State private var isSeedingHSK = false
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
    private struct SupportMailDraft: Identifiable {
        let id = UUID()
        let subject: String
        let recipients: [String]
        let body: String
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
                    isLoginGatePresented = true
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(AppColors.onAccent)
                        .background(Capsule().fill(AppColors.accent))
                }
                .buttonStyle(.plain)
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

    private var hskLevelBinding: HSKLevel {
        get { HSKLevel(rawValue: hskLevel) ?? .hsk1 }
        nonmutating set { Task { await changeHSKLevel(to: newValue) } }
    }

    private var hskLevelSection: some View {
        Section("Level") {
            NavigationLink {
                HSKLevelPickerView(
                    selectedLevel: Binding<HSKLevel>(
                        get: { hskLevelBinding },
                        set: { hskLevelBinding = $0 }
                    ),
                    isSeedingHSK: isSeedingHSK
                )
            } label: {
                HStack {
                    Text("Level")
                    Spacer()
                    if isSeedingHSK {
                        ProgressView()
                    } else {
                        Text(hskLevelBinding.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isSeedingHSK)
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
                hskLevelSection
                subscriptionSection
                supportSection
                privacyPolicySection
                deleteAccountSection
            }
            .navigationTitle("Settings")
            .fullScreenCover(isPresented: $isLoginGatePresented) {
                LoginGateView(signInPresenter: $signInPresenter) {
                    isLoginGatePresented = false
                    pendingPaywallPresentation = false
                }
            }
            .fullScreenCover(isPresented: $isPaywallPresented) {
                PaywallScreen()
            }
            .sheet(isPresented: $isPrivacyPolicyPresented) {
                if let privacyURL = AppConfig.privacyPolicyURL {
                    InAppSafariView(url: privacyURL)
                }
            }
            .sheet(isPresented: $isTermsOfServicePresented) {
                if let termsURL = AppConfig.termsOfServiceURL {
                    InAppSafariView(url: termsURL)
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
            .onChange(of: authManager.user?.id) { _, _ in
                if authManager.user != nil {
                    isLoginGatePresented = false
                }
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

    private var currentErrorMessage: String? {
        if case .error(let message) = authManager.authStatus {
            return message
        }
        return errorMessage
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

    private func deleteAccountErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIClientError,
           case APIClientError.httpError(let statusCode) = apiError,
           statusCode == 401 {
            return "Session expired. Please sign in again."
        }

        return "Unable to delete your account right now."
    }

    @MainActor
    private func changeHSKLevel(to level: HSKLevel) async {
        guard !isSeedingHSK else { return }
        hskLevel = level.rawValue
        isSeedingHSK = true
        defer { isSeedingHSK = false }
        await cardStore.seedHSKCards(level: level, userId: authManager.user?.id)
    }

    private func presentPaywall() {
        guard authManager.user == nil else {
            isPaywallPresented = true
            return
        }
        pendingPaywallPresentation = true
        isLoginGatePresented = true
    }

    private func handlePendingPaywallIfNeeded() {
        guard pendingPaywallPresentation, authManager.user != nil else { return }
        pendingPaywallPresentation = false
        isPaywallPresented = true
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

private struct HSKLevelPickerView: View {
    @Binding var selectedLevel: HSKLevel
    let isSeedingHSK: Bool
    @State private var isHSKInfoPresented = false

    var body: some View {
        List {
            ForEach(HSKLevel.allCases, id: \.rawValue) { (level: HSKLevel) in
                Button {
                    selectedLevel = level
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(level.displayName)
                                .font(.body.weight(.semibold))
                            Text(level.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(level.cumulativeWordCount) words")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if selectedLevel == level {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSeedingHSK)
            }

            if AppConfig.hskInfoURL != nil {
                Button {
                    isHSKInfoPresented = true
                } label: {
                    Label("Learn more about HSK", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(isSeedingHSK)
            }
        }
        .sheet(isPresented: $isHSKInfoPresented) {
            if let hskInfoURL = AppConfig.hskInfoURL {
                InAppSafariView(url: hskInfoURL)
            }
        }
        .navigationTitle("Level")
    }
}

#Preview {
    SettingsView(signInPresenter: .constant(nil))
        .environmentObject(AuthManager.shared)
        .environmentObject(FlashcardStore())
        .environmentObject(SubscriptionManager.shared)
}
