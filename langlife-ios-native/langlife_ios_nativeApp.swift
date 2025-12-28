//
//  langlife_ios_nativeApp.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import Auth
import GoogleSignIn
import RevenueCat
import SwiftUI

@main
struct langlife_ios_nativeApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var cardStore = FlashcardStore()
    @StateObject private var sceneStore = SpeakSceneStore()
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var signInPresenter: UIViewController?

    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(
            with: Configuration.Builder(withAPIKey: AppConfig.revenueCatAPIKey)
                .with(storeKitVersion: .storeKit2)
                .build()
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(signInPresenter: $signInPresenter)
                .environmentObject(authManager)
                .environmentObject(cardStore)
                .environmentObject(sceneStore)
                .environmentObject(subscriptionManager)
                .tint(AppColors.accent)
                .background(
                    SignInPresenter(presenter: $signInPresenter)
                        .allowsHitTesting(false)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                )
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    subscriptionManager.start()
                    await subscriptionManager.refresh()
                    await subscriptionManager.syncAppUser(id: authManager.user?.id.uuidString)
                }
                .onChange(of: authManager.user?.id) { _, newValue in
                    Task {
                        await subscriptionManager.syncAppUser(id: newValue?.uuidString)
                    }
                }
        }
    }
}
