import AuthenticationServices
import SwiftUI

enum SignInProvider: Equatable {
    case apple
    case google
}

struct SignInOptionsSheet: View {
    let onSelect: (SignInProvider) -> Void

    var body: some View {
        SignInOptionsView(onSelect: onSelect, title: "Sign in to continue")
    }
}

struct SignInOptionsView: View {
    let onSelect: (SignInProvider) -> Void
    let title: String?

    private let buttonHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            AppleSignInButton {
                onSelect(.apple)
            }
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .accessibilityLabel("Sign in with Apple")

            GoogleSignInButton(height: buttonHeight) {
                onSelect(.google)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

private struct AppleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 28
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func didTap() {
            action()
        }
    }
}

private struct GoogleSignInButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let action: () -> Void
    let height: CGFloat

    init(height: CGFloat, action: @escaping () -> Void) {
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("GoogleLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)

                Text("Sign in with Google")
                    .font(.title3.weight(.semibold))
                    .minimumScaleFactor(0.9)
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                Capsule()
                    .fill(Color.black)
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel("Sign in with Google")
    }
}
