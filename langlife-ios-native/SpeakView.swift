//
//  SpeakView.swift
//  langlife-ios-native
//
//  Created by Naman Kamra on 2025/12/21.
//

import Auth
import Foundation
import SwiftUI
import UIKit

struct SpeakView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var cardStore: FlashcardStore
    @EnvironmentObject private var sceneStore: SpeakSceneStore
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @Binding var signInPresenter: UIViewController?
    @Binding var generateRequestID: UUID
    @Binding var isAddScenePresented: Bool
    @Binding var isAddSceneEnabled: Bool
    @Binding var isGenerateSceneEnabled: Bool

    @State private var actionErrorMessage: String?
    @State private var selectedSceneId: UUID?
    @State private var selectedScene: SpeakScene?
    @State private var isCreatingScene = false
    @State private var addSceneError: String?
    @State private var isGeneratingScene = false
    @State private var isLoginGatePresented = false
    @State private var pendingSceneId: UUID?
    @State private var pendingAddScene = false
    @State private var pendingGenerateScene = false
    @State private var isPaywallPresented = false
    @State private var isVoiceSessionPresented = false
    @State private var pendingVoiceSession = false

    private let creationRepository = SpeakSceneCreationRepository()
    private let generationRepository = SpeakSceneGenerationRepository()
    private var isSceneLimitReached: Bool {
        !subscriptionManager.isPro
            && sceneStore.scenes.count >= SubscriptionLimits.freeSceneLimit
    }
    var body: some View {
        ScrollView {
            Button {
                requestVoiceSession()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(AppColors.onAccent)
                        .background(AppColors.accent, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Practice")
                            .font(.headline)
                        Text("Have a conversation with an AI tutor")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            TagFlowLayout(spacing: 12, rowSpacing: 12) {
                if isGeneratingScene {
                    Capsule()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(minHeight: 44)
                        .frame(minWidth: 96, maxWidth: 160, alignment: .leading)
                        .shimmer(isActive: true, cornerRadius: 22)
                        .clipShape(Capsule())
                }

                ForEach(sceneStore.scenes) { scene in
                    Button {
                        requestSceneSelection(scene)
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

            if sceneStore.isLoading {
                ProgressView()
                    .padding(.top, 12)
            }

            if let actionErrorMessage {
                Text(actionErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            } else if let errorMessage = sceneStore.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(sceneStore.isOfflineNotice ? Color.secondary : .red)
                    .padding(.top, 8)
            }

        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $selectedScene) { scene in
            SpeakSceneDetailView(scene: scene) { deletedScene in
                sceneStore.removeScene(id: deletedScene.id, userId: authManager.user?.id)
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
        .fullScreenCover(isPresented: $isLoginGatePresented) {
            LoginGateView(signInPresenter: $signInPresenter) {
                clearPendingActions()
                isLoginGatePresented = false
            }
        }
        .fullScreenCover(isPresented: $isPaywallPresented) {
            PaywallScreen()
        }
        .fullScreenCover(isPresented: $isVoiceSessionPresented) {
            VoiceSessionView()
                .onDisappear {
                    Task {
                        await cardStore.refresh(for: authManager.user?.id)
                    }
                }
        }
        .refreshable {
            await sceneStore.refresh(for: authManager.user?.id)
        }
        .task {
            await loadScenesIfNeeded()
        }
        .onChange(of: authManager.user?.id) { _, _ in
            Task {
                await loadScenesIfNeeded()
                await completePendingActionsIfNeeded()
            }
            if authManager.user != nil {
                isLoginGatePresented = false
            }
            actionErrorMessage = nil
            updateAddSceneAvailability()
            updateGenerateSceneAvailability()
            if isAddScenePresented {
                addSceneError = authManager.user == nil ? "Please sign in to add a scene." : nil
            }
        }
        .onChange(of: scenePhase) { _ in
            if scenePhase == .active, let userId = authManager.user?.id {
                Task {
                    await SceneSyncService.shared.syncIfNeeded(userId: userId)
                }
            }
        }
        .onChange(of: generateRequestID) { _, _ in
            handleGenerateSceneRequest()
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
            guard newValue else { return }
            guard authManager.user != nil else {
                setPendingAddScene()
                isAddScenePresented = false
                presentLoginGate()
                return
            }
            guard !isSceneLimitReached else {
                isAddScenePresented = false
                isPaywallPresented = true
                return
            }
            addSceneError = nil
        }
    }

    @MainActor
    private func loadScenesIfNeeded() async {
        await sceneStore.loadIfNeeded(for: authManager.user?.id)
        if let userId = authManager.user?.id {
            await SceneSyncService.shared.syncIfNeeded(userId: userId)
        }
        if authManager.user == nil {
            selectedSceneId = nil
            selectedScene = nil
        }
    }

    private func requestSceneSelection(_ scene: SpeakScene) {
        guard authManager.user != nil else {
            setPendingScene(scene)
            presentLoginGate()
            return
        }
        selectedSceneId = scene.id
        selectedScene = scene
    }

    private func handleGenerateSceneRequest() {
        guard authManager.user != nil else {
            setPendingGenerateScene()
            presentLoginGate()
            return
        }
        guard !isSceneLimitReached else {
            isPaywallPresented = true
            return
        }
        Task {
            await generateScene()
        }
    }

    @MainActor
    private func completePendingActionsIfNeeded() async {
        guard authManager.user != nil else { return }

        if let pendingSceneId {
            if let scene = sceneStore.scenes.first(where: { $0.id == pendingSceneId }) {
                selectedSceneId = scene.id
                selectedScene = scene
            }
            self.pendingSceneId = nil
            return
        }

        if pendingAddScene {
            pendingAddScene = false
            isAddScenePresented = true
            return
        }

        if pendingGenerateScene {
            pendingGenerateScene = false
            guard !isSceneLimitReached else {
                isPaywallPresented = true
                return
            }
            await generateScene()
            return
        }

        if pendingVoiceSession {
            pendingVoiceSession = false
            guard subscriptionManager.isPro || isVoiceLimitAvailable else {
                isPaywallPresented = true
                return
            }
            isVoiceSessionPresented = true
        }
    }

    private func setPendingScene(_ scene: SpeakScene) {
        pendingSceneId = scene.id
        pendingAddScene = false
        pendingGenerateScene = false
        pendingVoiceSession = false
    }

    private func setPendingAddScene() {
        pendingAddScene = true
        pendingGenerateScene = false
        pendingSceneId = nil
        pendingVoiceSession = false
    }

    private func setPendingGenerateScene() {
        pendingGenerateScene = true
        pendingAddScene = false
        pendingSceneId = nil
        pendingVoiceSession = false
    }

    private func clearPendingActions() {
        pendingSceneId = nil
        pendingAddScene = false
        pendingGenerateScene = false
        pendingVoiceSession = false
    }

    private func requestVoiceSession() {
        guard authManager.user != nil else {
            setPendingVoiceSession()
            presentLoginGate()
            return
        }
        guard subscriptionManager.isPro || isVoiceLimitAvailable else {
            isPaywallPresented = true
            return
        }
        isVoiceSessionPresented = true
    }

    private var isVoiceLimitAvailable: Bool {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let count = LocalVoiceSessionLimitStore.loadCount(userId: authManager.user?.id, dayStart: dayStart)
        return count < SubscriptionLimits.freeVoiceDailyLimit
    }

    private func setPendingVoiceSession() {
        pendingVoiceSession = true
        pendingSceneId = nil
        pendingAddScene = false
        pendingGenerateScene = false
    }

    private func presentLoginGate() {
        isLoginGatePresented = true
    }

    @MainActor
    private func generateScene() async {
        guard !isGeneratingScene else { return }
        guard authManager.user != nil else {
            actionErrorMessage = "Please sign in to generate a scene."
            return
        }
        guard !isSceneLimitReached else {
            isPaywallPresented = true
            return
        }

        isGeneratingScene = true
        actionErrorMessage = nil
        defer { isGeneratingScene = false }

        do {
            let excludeIds = sceneStore.scenes.map { $0.id.uuidString }
            let existingTitles = sceneStore.scenes.map { $0.title }
            let generated = try await generationRepository.generateScenes(
                count: 1,
                excludeIds: Array(excludeIds.prefix(50)),
                existingTitles: existingTitles,
                userId: authManager.user?.id
            )
            guard let scene = generated.first else {
                actionErrorMessage = "No new scenes available right now."
                return
            }
            if let userId = authManager.user?.id {
                sceneStore.upsertScene(scene, userId: userId)
            }
            selectedSceneId = scene.id
            selectedScene = scene
            await cardStore.refresh(for: authManager.user?.id)
        } catch {
            actionErrorMessage = mapGenerateSceneError(error)
        }
    }

    @MainActor
    private func addScene(prompt: String) async -> Bool {
        guard !isCreatingScene else { return false }
        guard authManager.user != nil else {
            addSceneError = "Please sign in to add a scene."
            return false
        }
        guard !isSceneLimitReached else {
            isPaywallPresented = true
            return false
        }

        isCreatingScene = true
        addSceneError = nil
        defer { isCreatingScene = false }

        do {
            let scene = try await creationRepository.createScene(
                prompt: prompt,
                existingTitles: sceneStore.scenes.map { $0.title },
                userId: authManager.user?.id
            )
            if let userId = authManager.user?.id {
                sceneStore.upsertScene(scene, userId: userId)
            }
            await cardStore.refresh(for: authManager.user?.id)
            return true
        } catch {
            addSceneError = mapAddSceneError(error)
            return false
        }
    }

    private func mapAddSceneError(_ error: Error) -> String {
        if case SceneGenerationError.invalidResponse = error {
            return "Unable to create that scene right now."
        }
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
        if case SceneGenerationError.invalidResponse = error {
            return "Unable to generate a scene right now."
        }
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
        signInPresenter: .constant(nil),
        generateRequestID: .constant(UUID()),
        isAddScenePresented: .constant(false),
        isAddSceneEnabled: .constant(true),
        isGenerateSceneEnabled: .constant(true)
    )
        .environmentObject(AuthManager.shared)
        .environmentObject(FlashcardStore())
        .environmentObject(SpeakSceneStore())
        .environmentObject(SubscriptionManager.shared)
}
