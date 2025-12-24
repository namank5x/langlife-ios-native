//
//  ContentView.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import SwiftUI
import UIKit

struct ContentView: View {
    enum Tab {
        case study
        case speak
    }

    @Binding var signInPresenter: UIViewController?
    @State private var selection: Tab = .study
    @State private var isSettingsPresented = false
    @State private var generateSceneRequestID = UUID()
    @State private var isAddCardPresented = false
    @State private var isAddCardEnabled = true
    @State private var isAddScenePresented = false
    @State private var isAddSceneEnabled = true
    @State private var isGenerateSceneEnabled = true

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                StudyView(
                    signInPresenter: $signInPresenter,
                    isAddCardPresented: $isAddCardPresented,
                    isAddCardEnabled: $isAddCardEnabled
                )
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                isAddCardPresented = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add card")
                            .disabled(!isAddCardEnabled)

                            Button {
                                isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
            }
            .tabItem {
                Label("Study", systemImage: "book")
            }
            .tag(Tab.study)

            NavigationStack {
                SpeakView(
                    signInPresenter: $signInPresenter,
                    generateRequestID: $generateSceneRequestID,
                    isAddScenePresented: $isAddScenePresented,
                    isAddSceneEnabled: $isAddSceneEnabled,
                    isGenerateSceneEnabled: $isGenerateSceneEnabled
                )
                    .navigationTitle("Speak")
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                generateSceneRequestID = UUID()
                            } label: {
                                Image(systemName: "sparkles")
                            }
                            .accessibilityLabel("Generate scene")
                            .disabled(!isGenerateSceneEnabled)

                            Button {
                                isAddScenePresented = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add scene")
                            .disabled(!isAddSceneEnabled)

                            Button {
                                isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                        }
                    }
            }
            .tabItem {
                Label("Speak", systemImage: "mic")
            }
            .tag(Tab.speak)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(signInPresenter: $signInPresenter)
        }
    }
}

#Preview {
    ContentView(signInPresenter: .constant(nil))
        .environmentObject(AuthManager.shared)
}
