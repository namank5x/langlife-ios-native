import SwiftUI

struct AuthLoadingCard: View {
    let title: String
    let subtitle: String?
    let phrases: [String]
    let showsSpinner: Bool
    let showShimmer: Bool

    init(
        title: String,
        subtitle: String? = nil,
        phrases: [String] = [],
        showsSpinner: Bool = true,
        showShimmer: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.phrases = phrases
        self.showsSpinner = showsSpinner
        self.showShimmer = showShimmer
    }

    var body: some View {
        VStack(spacing: 16) {
            Image("LangLifeLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            if showsSpinner {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColors.accent)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !phrases.isEmpty {
                    RotatingLoadingText(
                        phrases: phrases,
                        font: .system(size: 15, weight: .medium, design: .rounded),
                        color: .secondary,
                        minHeight: 20,
                        showsShimmerLine: showShimmer
                    )
                    .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    AuthLoadingCard(
        title: "Getting things ready",
        subtitle: "Syncing your profile...",
        phrases: ["Syncing your profile...", "Setting things up..."],
        showShimmer: false
    )
}
