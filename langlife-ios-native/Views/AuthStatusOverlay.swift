import SwiftUI

struct AuthStatusOverlay: View {
    let status: AuthStatus
    let onCancel: (() -> Void)?
    let onDismissError: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let signInPhrases = [
        "Securing your session…",
        "Syncing your profile…",
        "Almost there…"
    ]

    var body: some View {
        switch status {
        case .signingIn(let provider, _):
            overlay(
                title: "Finishing sign-in",
                subtitle: nil,
                phrases: signInPhrases,
                showsSpinner: true,
                actionTitle: nil,
                action: nil
            )
            .accessibilityLabel("Signing in. Please wait.")
        case .error(let message):
            overlay(
                title: "Something went wrong",
                subtitle: message,
                phrases: [],
                showsSpinner: false,
                actionTitle: "Dismiss",
                action: onDismissError
            )
            .accessibilityLabel("Sign-in failed. \(message)")
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func overlay(
        title: String,
        subtitle: String?,
        phrases: [String],
        showsSpinner: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        ZStack {
            OnboardingBackground()

            Color.black
                .opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if !showsSpinner {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }

                AuthLoadingCard(
                    title: title,
                    subtitle: subtitle,
                    phrases: showsSpinner ? phrases : [],
                    showsSpinner: showsSpinner
                )

                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.accent)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .accessibilityElement(children: .combine)
            .transition(reduceMotion ? .identity : .opacity)
        }
        .transition(reduceMotion ? .identity : .opacity)
    }
}
