import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(.systemOrange).opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: -140, y: -200)

            Circle()
                .fill(Color(.systemTeal).opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: 160, y: 140)
        }
    }
}
