import SwiftUI

struct RotatingLoadingText: View {
    let phrases: [String]
    let interval: TimeInterval
    let font: Font
    let color: Color
    let minHeight: CGFloat
    let showsShimmerLine: Bool
    let lineWidth: CGFloat
    let lineHeight: CGFloat
    let lineColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    init(
        phrases: [String],
        interval: TimeInterval = 2.0,
        font: Font = .subheadline,
        color: Color = .secondary,
        minHeight: CGFloat = 0,
        showsShimmerLine: Bool = true,
        lineWidth: CGFloat = 140,
        lineHeight: CGFloat = 3,
        lineColor: Color = .secondary.opacity(0.35)
    ) {
        self.phrases = phrases
        self.interval = interval
        self.font = font
        self.color = color
        self.minHeight = minHeight
        self.showsShimmerLine = showsShimmerLine
        self.lineWidth = lineWidth
        self.lineHeight = lineHeight
        self.lineColor = lineColor
    }

    var body: some View {
        let phrase = phrases.isEmpty ? "Loading..." : phrases[index % phrases.count]
        VStack(spacing: 10) {
            Text(phrase)
                .id(phrase)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .transition(reduceMotion ? .identity : .opacity)

            if showsShimmerLine {
                RoundedRectangle(cornerRadius: lineHeight / 2, style: .continuous)
                    .fill(lineColor)
                    .frame(width: lineWidth, height: lineHeight)
                    .shimmer(isActive: !reduceMotion, cornerRadius: lineHeight / 2, animationDuration: 2.0)
                    .opacity(reduceMotion ? 0.5 : 1)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(minHeight: minHeight)
        .task(id: reduceMotion) {
            guard !reduceMotion, phrases.count > 1 else { return }
            await rotatePhrases()
        }
    }

    @MainActor
    private func rotatePhrases() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard phrases.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                index = (index + 1) % phrases.count
            }
        }
    }
}
