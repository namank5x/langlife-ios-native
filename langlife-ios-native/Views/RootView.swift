import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingVersionSeen") private var onboardingVersionSeen = 0
    @AppStorage("guestModeEnabled") private var guestModeEnabled = false
    @Binding var signInPresenter: UIViewController?

    private let currentOnboardingVersion = 2

    var body: some View {
        mainContent
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: authManager.authPhase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: guestModeEnabled)
        .onChange(of: authManager.authPhase) { _, newValue in
            if newValue == .signedIn {
                guestModeEnabled = false
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if onboardingVersionSeen < currentOnboardingVersion {
            OnboardingView {
                onboardingVersionSeen = currentOnboardingVersion
            }
        } else if authManager.authPhase == .signedIn {
            ContentView(signInPresenter: $signInPresenter)
                .transition(reduceMotion ? .identity : .opacity)
        } else if guestModeEnabled {
            ContentView(signInPresenter: $signInPresenter)
                .transition(reduceMotion ? .identity : .opacity)
        } else {
            switch authManager.authPhase {
            case .checking:
                AuthLoadingView()
                    .transition(reduceMotion ? .identity : .opacity)
            case .signedOut:
                LoginGateView(signInPresenter: $signInPresenter) {
                    guestModeEnabled = true
                }
                    .transition(reduceMotion ? .identity : .opacity)
            case .signedIn:
                ContentView(signInPresenter: $signInPresenter)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }
}
