import SwiftUI

struct AuthLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingBackground()

            AuthLoadingCard(
                title: "Getting things ready",
                subtitle: nil,
                phrases: [],
                showsSpinner: true
            )
            .opacity(reduceMotion ? 1 : 0.95)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AuthLoadingView()
}
