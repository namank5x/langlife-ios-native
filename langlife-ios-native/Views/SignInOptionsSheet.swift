import SwiftUI

enum SignInProvider {
    case apple
    case google
}

struct SignInOptionsSheet: View {
    let onSelect: (SignInProvider) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign in to continue")
                .font(.headline)

            Button {
                onSelect(.apple)
            } label: {
                Label("Sign in with Apple", systemImage: "apple.logo")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .neutralProminentButton()

            Button {
                onSelect(.google)
            } label: {
                Text("Sign in with Google")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .neutralProminentButton()
        }
        .padding()
    }
}
