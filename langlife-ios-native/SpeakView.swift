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
    @State private var localSignInPresenter: UIViewController?
    @State private var isSigningIn = false
    @State private var isSignInOptionsPresented = false
    @State private var pendingSignInProvider: SignInProvider?
    @State private var shouldStartSignIn = false
    @State private var signInError: String?
    @State private var pendingSceneId: UUID?
    @State private var pendingAddScene = false
    @State private var pendingGenerateScene = false
    @State private var isPaywallPresented = false

    private let creationRepository = SpeakSceneCreationRepository()
    private let generationRepository = SpeakSceneGenerationRepository()
    private var isSceneLimitReached: Bool {
        !subscriptionManager.isPro
            && sceneStore.scenes.count >= SubscriptionLimits.freeSceneLimit
    }
    private var sceneLimitMessage: String {
        "Free plan includes up to \(SubscriptionLimits.freeSceneLimit) scenes. Upgrade to Lang Life Pro to add more."
    }

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

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
        }
        .background(Color(.systemGroupedBackground))
        .background(
            SignInPresenter(presenter: $localSignInPresenter)
                .allowsHitTesting(false)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        )
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
        .sheet(
            isPresented: $isSignInOptionsPresented,
            onDismiss: {
                if pendingSignInProvider == nil {
                    clearPendingActions()
                }
                shouldStartSignIn = pendingSignInProvider != nil
                startPendingSignInIfPossible()
            },
            content: {
                SignInOptionsSheet(
                    onSelect: { provider in
                        pendingSignInProvider = provider
                        isSignInOptionsPresented = false
                    }
                )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
        )
        .sheet(isPresented: $isPaywallPresented) {
            PaywallScreen()
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
            actionErrorMessage = nil
            updateAddSceneAvailability()
            updateGenerateSceneAvailability()
            if isAddScenePresented {
                addSceneError = authManager.user == nil ? "Please sign in to add a scene." : nil
            }
        }
        .onChange(of: scenePhase) { _ in
            startPendingSignInIfPossible()
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
                presentSignInOptions()
                return
            }
            guard !isSceneLimitReached else {
                isAddScenePresented = false
                actionErrorMessage = sceneLimitMessage
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
            presentSignInOptions()
            return
        }
        selectedSceneId = scene.id
        selectedScene = scene
    }

    private func handleGenerateSceneRequest() {
        guard authManager.user != nil else {
            setPendingGenerateScene()
            presentSignInOptions()
            return
        }
        guard !isSceneLimitReached else {
            actionErrorMessage = sceneLimitMessage
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
                actionErrorMessage = sceneLimitMessage
                isPaywallPresented = true
                return
            }
            await generateScene()
        }
    }

    private func setPendingScene(_ scene: SpeakScene) {
        pendingSceneId = scene.id
        pendingAddScene = false
        pendingGenerateScene = false
    }

    private func setPendingAddScene() {
        pendingAddScene = true
        pendingGenerateScene = false
        pendingSceneId = nil
    }

    private func setPendingGenerateScene() {
        pendingGenerateScene = true
        pendingAddScene = false
        pendingSceneId = nil
    }

    private func clearPendingActions() {
        pendingSceneId = nil
        pendingAddScene = false
        pendingGenerateScene = false
    }

    private func presentSignInOptions() {
        guard !isSigningIn else { return }
        signInError = nil
        pendingSignInProvider = nil
        shouldStartSignIn = false
        isSignInOptionsPresented = true
    }

    @MainActor
    private func signInWithApple() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            try await authManager.signInWithApple()
        } catch {
            signInError = error.localizedDescription
            clearPendingActions()
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil

        do {
            let presenter = signInPresenter ?? localSignInPresenter
            try await authManager.signInWithGoogle(presentingViewController: presenter)
            isSigningIn = false
        } catch {
            isSigningIn = false
            if isGoogleSignInCancelled(error) {
                clearPendingActions()
                return
            }
            signInError = error.localizedDescription
            clearPendingActions()
        }
    }

    private func isGoogleSignInCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.GIDSignIn"
            && nsError.code == -5
    }

    private func performSignIn(_ provider: SignInProvider) async {
        switch provider {
        case .apple:
            await signInWithApple()
        case .google:
            await signInWithGoogle()
        }
    }

    private func startPendingSignInIfPossible() {
        guard shouldStartSignIn, scenePhase == .active,
              let provider = pendingSignInProvider else { return }
        shouldStartSignIn = false
        Task { @MainActor in
            await Task.yield()
            await waitForStablePresentation()
            defer { pendingSignInProvider = nil }
            await performSignIn(provider)
        }
    }

    @MainActor
    private func waitForStablePresentation() async {
        for _ in 0..<30 {
            guard scenePhase == .active else {
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }

            if let presenter = signInPresenter ?? localSignInPresenter {
                let root = presenter.view.window?.rootViewController ?? presenter
                let top = topViewController(from: root)
                if top.view.window != nil,
                   !top.isBeingPresented,
                   !top.isBeingDismissed {
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func topViewController(from rootViewController: UIViewController) -> UIViewController {
        var topViewController = rootViewController
        while true {
            if let presented = topViewController.presentedViewController {
                topViewController = presented
                continue
            }
            if let navigationController = topViewController as? UINavigationController,
               let visibleViewController = navigationController.visibleViewController {
                topViewController = visibleViewController
                continue
            }
            if let tabBarController = topViewController as? UITabBarController,
               let selectedViewController = tabBarController.selectedViewController {
                topViewController = selectedViewController
                continue
            }
            break
        }
        return topViewController
    }

    @MainActor
    private func generateScene() async {
        guard !isGeneratingScene else { return }
        guard authManager.user != nil else {
            actionErrorMessage = "Please sign in to generate a scene."
            return
        }
        guard !isSceneLimitReached else {
            actionErrorMessage = sceneLimitMessage
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
            addSceneError = sceneLimitMessage
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
