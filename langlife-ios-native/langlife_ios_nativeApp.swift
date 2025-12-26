//
//  langlife_ios_nativeApp.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import GoogleSignIn
import SwiftUI

@main
struct langlife_ios_nativeApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var cardStore = FlashcardStore()
    @StateObject private var sceneStore = SpeakSceneStore()
    @State private var signInPresenter: UIViewController?

    var body: some Scene {
        WindowGroup {
            ContentView(signInPresenter: $signInPresenter)
                .environmentObject(authManager)
                .environmentObject(cardStore)
                .environmentObject(sceneStore)
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
        }
    }
}
