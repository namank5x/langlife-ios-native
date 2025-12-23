import SwiftUI

private struct NeutralProminentButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .foregroundStyle(AppColors.onAccent)
    }
}

extension View {
    func neutralProminentButton() -> some View {
        modifier(NeutralProminentButton())
    }
}
