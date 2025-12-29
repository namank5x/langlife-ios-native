import SwiftUI

struct AuthLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 16) {
                Image("LangLifeLogo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)

                ProgressView()
                    .progressViewStyle(.circular)

                Text("Getting things ready")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(reduceMotion ? 1 : 0.9)
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AuthLoadingView()
}
