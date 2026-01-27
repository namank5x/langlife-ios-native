import SwiftUI

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    let animationDuration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var startTime = Date()

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && !reduceMotion {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            let width = proxy.size.width
                            let height = proxy.size.height
                            let highlightWidth = max(width * 1.6, 140)
                            let elapsed = context.date.timeIntervalSince(startTime)
                            let phase = elapsed.truncatingRemainder(dividingBy: animationDuration) / animationDuration
                            let travel = width + highlightWidth
                            let xOffset = (CGFloat(phase) * travel) - highlightWidth
                            let shimmerColor = colorScheme == .dark ? Color.white : Color.black
                            let opacities = shimmerOpacities()
                            ZStack(alignment: .leading) {
                                LinearGradient(
                                    colors: [
                                        shimmerColor.opacity(opacities.low),
                                        shimmerColor.opacity(opacities.high),
                                        shimmerColor.opacity(opacities.low),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: highlightWidth, height: height)
                                .offset(x: xOffset)
                                .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
                                .compositingGroup()
                            }
                            .frame(width: width, height: height, alignment: .leading)
                            .mask {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        startTime = Date()
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    startTime = Date()
                }
            }
    }

    private func shimmerOpacities() -> (low: Double, high: Double) {
        let isHighContrast = colorSchemeContrast == .increased
        if colorScheme == .dark {
            return (low: isHighContrast ? 0.18 : 0.12, high: isHighContrast ? 0.5 : 0.35)
        }
        return (low: isHighContrast ? 0.12 : 0.06, high: isHighContrast ? 0.32 : 0.18)
    }
}

extension View {
    func shimmer(
        isActive: Bool,
        cornerRadius: CGFloat,
        animationDuration: Double = 1.4
    ) -> some View {
        modifier(
            ShimmerModifier(
                isActive: isActive,
                cornerRadius: cornerRadius,
                animationDuration: animationDuration
            )
        )
    }
}
