//
//  SpeakView.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import Auth
import Foundation
import SwiftUI

struct SpeakView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var randomRequestID: UUID

    @State private var scenes: [SpeakScene] = SpeakSceneSeed.defaults
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSceneId: UUID?
    @State private var selectedScene: SpeakScene?

    private let repository = SpeakRepository()

    var body: some View {
        ScrollView {
            TagFlowLayout(spacing: 12, rowSpacing: 12) {
                ForEach(scenes) { scene in
                    Button {
                        selectedSceneId = scene.id
                        selectedScene = scene
                    } label: {
                        Text(scene.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(
                                selectedSceneId == scene.id ? AppColors.onAccent : Color.primary
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44, alignment: .leading)
                            .background(
                                Capsule().fill(
                                    selectedSceneId == scene.id
                                        ? AppColors.accent
                                        : Color(.secondarySystemGroupedBackground)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if isLoading {
                ProgressView()
                    .padding(.top, 12)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $selectedScene) { scene in
            SpeakSceneDetailView(scene: scene)
        }
        .task {
            await loadScenesIfNeeded()
        }
        .onChange(of: authManager.user?.id) { _, _ in
            Task {
                await loadScenesIfNeeded()
            }
        }
        .onChange(of: randomRequestID) { _, _ in
            selectRandomScene()
        }
    }

    @MainActor
    private func loadScenesIfNeeded() async {
        guard let userId = authManager.user?.id else {
            isLoading = false
            errorMessage = nil
            scenes = SpeakSceneSeed.defaults
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let fetched = try await repository.fetchScenes(for: userId)
            guard authManager.user?.id == userId else { return }
            scenes = fetched.isEmpty ? SpeakSceneSeed.defaults : fetched
        } catch {
            guard authManager.user?.id == userId else { return }
            errorMessage = "Unable to load scenes right now."
            scenes = SpeakSceneSeed.defaults
        }
    }

    @MainActor
    private func selectRandomScene() {
        guard !scenes.isEmpty else { return }
        if scenes.count == 1 {
            selectedSceneId = scenes.first?.id
            return
        }

        let candidates = scenes.filter { $0.id != selectedSceneId }
        if let random = candidates.randomElement() {
            selectedSceneId = random.id
        } else if let random = scenes.randomElement() {
            selectedSceneId = random.id
        }
    }
}

#Preview {
    SpeakView(randomRequestID: .constant(UUID()))
        .environmentObject(AuthManager.shared)
}
