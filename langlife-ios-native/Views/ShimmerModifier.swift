import SwiftUI

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    let animationDuration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            ZStack(alignment: .leading) {
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.1),
                                        .white.opacity(0.35),
                                        .white.opacity(0.1),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: highlightWidth, height: height)
                                .offset(x: xOffset)
                                .blendMode(.plusLighter)
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
