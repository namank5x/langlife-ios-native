import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage("onboardingVersionSeen") private var onboardingVersionSeen = 0
    @Binding var signInPresenter: UIViewController?

    private let currentOnboardingVersion = 1

    var body: some View {
        Group {
            if onboardingVersionSeen < currentOnboardingVersion {
                OnboardingView {
                    onboardingVersionSeen = currentOnboardingVersion
                }
            } else if authManager.user == nil {
                LoginGateView(signInPresenter: $signInPresenter)
            } else {
                ContentView(signInPresenter: $signInPresenter)
            }
        }
    }
}
