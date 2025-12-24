import SwiftUI
import UIKit

struct AddSceneSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isSaving: Bool
    let errorMessage: String?
    let isSignedIn: Bool
    let onSave: (_ prompt: String) async -> Bool
    let onUpdate: () -> Void

    @State private var prompt = ""
    @State private var showSuccess = false
    @FocusState private var isPromptFocused: Bool

    private let minLength = 6
    private let maxLength = 200

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var promptError: String? {
        guard !trimmedPrompt.isEmpty else { return nil }
        if trimmedPrompt.count < minLength {
            return "Add a little more detail (at least 6 characters)."
        }
        if trimmedPrompt.count > maxLength {
            return "Keep it under 200 characters."
        }
        return nil
    }

    private var isFormValid: Bool {
        trimmedPrompt.count >= minLength && trimmedPrompt.count <= maxLength
    }

    private enum ButtonState {
        case idle
        case saving
        case success
    }

    private var buttonState: ButtonState {
        if showSuccess {
            return .success
        }
        return isSaving ? .saving : .idle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scene idea")
                            .font(.headline)
                        TextField(
                            "Describe the scene you want (e.g., Order bubble tea with less ice)",
                            text: $prompt,
                            axis: .vertical
                        )
                        .font(.system(size: 20, weight: .semibold))
                        .focused($isPromptFocused)
                        .disabled(isSaving)
                        .lineLimit(4, reservesSpace: true)
                        .padding(16)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )
                    }

                    if let promptError {
                        Text(promptError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !isSignedIn {
                        Text("Please sign in to add a scene.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle("New Scene")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        triggerTapHaptic()
                        Task {
                            let success = await onSave(trimmedPrompt)
                            if success {
                                await showSuccessState()
                                dismiss()
                            }
                        }
                    } label: {
                        ZStack {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Creating...")
                            }
                            .opacity(0)
                            .accessibilityHidden(true)

                            if buttonState == .idle {
                                Text("Create")
                                    .lineLimit(1)
                                    .transition(.opacity.combined(with: .scale))
                            }
                            if buttonState == .saving {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Creating...")
                                }
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .scale))
                            }
                            if buttonState == .success {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                    Text("Created")
                                }
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSaving)
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showSuccess)
                    }
                    .disabled(!isFormValid || isSaving || !isSignedIn)
                }
            }
            .onAppear {
                isPromptFocused = true
                showSuccess = false
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: prompt) { _, _ in
                onUpdate()
            }
        }
    }

    private func triggerTapHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    private func triggerSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    @MainActor
    private func showSuccessState() async {
        triggerSuccessHaptic()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showSuccess = true
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
    }
}

#Preview {
    AddSceneSheet(
        isSaving: false,
        errorMessage: nil,
        isSignedIn: true,
        onSave: { _ in
            await Task.yield()
            return true
        },
        onUpdate: {}
    )
}
