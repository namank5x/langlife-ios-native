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
    @State private var randomSceneRequestID = UUID()

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                StudyView()
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add")

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
                SpeakView(randomRequestID: $randomSceneRequestID)
                    .navigationTitle("Speak")
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                randomSceneRequestID = UUID()
                            } label: {
                                Image(systemName: "sparkles")
                            }
                            .accessibilityLabel("Random scene")

                            Button {
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add")

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
