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
    @Binding var generateRequestID: UUID
    @Binding var isAddScenePresented: Bool
    @Binding var isAddSceneEnabled: Bool
    @Binding var isGenerateSceneEnabled: Bool

    @State private var scenes: [SpeakScene] = SpeakSceneSeed.defaults
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSceneId: UUID?
    @State private var selectedScene: SpeakScene?
    @State private var isCreatingScene = false
    @State private var addSceneError: String?
    @State private var isGeneratingScene = false

    private let repository = SpeakRepository()
    private let creationRepository = SpeakSceneCreationRepository()
    private let generationRepository = SpeakSceneGenerationRepository()

    var body: some View {
        ScrollView {
            TagFlowLayout(spacing: 12, rowSpacing: 12) {
                if isGeneratingScene {
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(minHeight: 44)
                        .frame(minWidth: 96, maxWidth: 160, alignment: .leading)
                        .shimmer(isActive: true, cornerRadius: 22)
                        .clipShape(Capsule())
                }

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
            SpeakSceneDetailView(scene: scene) { deletedScene in
                scenes.removeAll { $0.id == deletedScene.id }
                if scenes.isEmpty {
                    scenes = SpeakSceneSeed.defaults
                }
                if selectedSceneId == deletedScene.id {
                    selectedSceneId = nil
                }
                selectedScene = nil
            }
        }
        .sheet(isPresented: $isAddScenePresented) {
            AddSceneSheet(
                isSaving: isCreatingScene,
                errorMessage: addSceneError,
                isSignedIn: authManager.user != nil,
                onSave: { prompt in
                    await addScene(prompt: prompt)
                },
                onUpdate: {
                    addSceneError = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadScenesIfNeeded()
        }
        .onChange(of: authManager.user?.id) { _, _ in
            Task {
                await loadScenesIfNeeded()
            }
            updateAddSceneAvailability()
            updateGenerateSceneAvailability()
            if isAddScenePresented {
                addSceneError = authManager.user == nil ? "Please sign in to add a scene." : nil
            }
        }
        .onChange(of: generateRequestID) { _, _ in
            Task {
                await generateScene()
            }
        }
        .onAppear {
            updateAddSceneAvailability()
            updateGenerateSceneAvailability()
        }
        .onChange(of: isCreatingScene) { _, _ in
            updateAddSceneAvailability()
        }
        .onChange(of: isGeneratingScene) { _, _ in
            updateGenerateSceneAvailability()
        }
        .onChange(of: isAddScenePresented) { _, newValue in
            if newValue {
                addSceneError = authManager.user == nil ? "Please sign in to add a scene." : nil
            }
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
    private func generateScene() async {
        guard !isGeneratingScene else { return }
        guard authManager.user != nil else {
            errorMessage = "Please sign in to generate a scene."
            return
        }

        isGeneratingScene = true
        errorMessage = nil
        defer { isGeneratingScene = false }

        do {
            let excludeIds = scenes.map { $0.id.uuidString }
            let generated = try await generationRepository.generateScenes(
                count: 1,
                excludeIds: Array(excludeIds.prefix(50))
            )
            guard let scene = generated.first else {
                errorMessage = "No new scenes available right now."
                return
            }
            scenes = [scene] + scenes.filter { $0.id != scene.id }
            selectedSceneId = scene.id
        } catch {
            errorMessage = mapGenerateSceneError(error)
        }
    }

    @MainActor
    private func addScene(prompt: String) async -> Bool {
        guard !isCreatingScene else { return false }
        guard authManager.user != nil else {
            addSceneError = "Please sign in to add a scene."
            return false
        }

        isCreatingScene = true
        addSceneError = nil
        defer { isCreatingScene = false }

        do {
            let scene = try await creationRepository.createScene(prompt: prompt)
            scenes = [scene] + scenes.filter { $0.id != scene.id }
            return true
        } catch {
            addSceneError = mapAddSceneError(error)
            return false
        }
    }

    private func mapAddSceneError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return "Unable to create that scene right now."
        }

        switch apiError {
        case .httpError(let statusCode):
            switch statusCode {
            case 400:
                return "Please describe the scene in a bit more detail."
            case 401:
                return "Please sign in to add a scene."
            default:
                return "Unable to create that scene right now."
            }
        }
    }

    private func updateAddSceneAvailability() {
        isAddSceneEnabled = !isCreatingScene
    }

    private func mapGenerateSceneError(_ error: Error) -> String {
        guard let apiError = error as? APIClientError else {
            return "Unable to generate a scene right now."
        }

        switch apiError {
        case .httpError(let statusCode):
            switch statusCode {
            case 400:
                return "Unable to generate a scene right now."
            case 401:
                return "Please sign in to generate a scene."
            case 409:
                return "No new scenes available right now."
            default:
                return "Unable to generate a scene right now."
            }
        }
    }

    private func updateGenerateSceneAvailability() {
        isGenerateSceneEnabled = !isGeneratingScene
    }
}

#Preview {
    SpeakView(
        generateRequestID: .constant(UUID()),
        isAddScenePresented: .constant(false),
        isAddSceneEnabled: .constant(true),
        isGenerateSceneEnabled: .constant(true)
    )
        .environmentObject(AuthManager.shared)
}
