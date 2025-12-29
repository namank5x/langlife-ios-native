import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingVersionSeen") private var onboardingVersionSeen = 0
    @Binding var signInPresenter: UIViewController?

    private let currentOnboardingVersion = 1

    var body: some View {
        Group {
            if onboardingVersionSeen < currentOnboardingVersion {
                OnboardingView {
                    onboardingVersionSeen = currentOnboardingVersion
                }
            } else {
                switch authManager.authPhase {
                case .checking:
                    AuthLoadingView()
                        .transition(reduceMotion ? .identity : .opacity)
                case .signedOut:
                    LoginGateView(signInPresenter: $signInPresenter)
                        .transition(reduceMotion ? .identity : .opacity)
                case .signedIn:
                    ContentView(signInPresenter: $signInPresenter)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authManager.authPhase)
    }
}
