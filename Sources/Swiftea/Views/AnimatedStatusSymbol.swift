import SwiftUI

struct AnimatedStatusSymbol: View {
    private static let animationDuration: TimeInterval = 1.35
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    let systemName: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let baseColor: Color
    let softHighlightColor: Color
    let brightHighlightColor: Color
    var cutoutRadius: CGFloat = 0

    private var frameWidth: CGFloat {
        fontSize * 1.8
    }

    private var frameHeight: CGFloat {
        fontSize * 1.6
    }

    private var gradientHeight: CGFloat {
        fontSize * 2.6
    }

    private var cutoutOffsets: [CGSize] {
        guard cutoutRadius > 0 else { return [] }

        let sampleCount = 24
        return (0..<sampleCount).map { index in
            let angle = (CGFloat(index) / CGFloat(sampleCount)) * (.pi * 2)
            return CGSize(
                width: cos(angle) * cutoutRadius,
                height: sin(angle) * cutoutRadius
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval)) { context in
            symbolBody(phase: Self.animationPhase(at: context.date))
        }
        .frame(width: frameWidth, height: frameHeight)
        .accessibilityHidden(true)
    }

    private func symbolBody(phase: CGFloat) -> some View {
        ZStack {
            ForEach(Array(cutoutOffsets.enumerated()), id: \.offset) { _, offset in
                glyph
                    .offset(x: offset.width, y: offset.height)
                    .blendMode(.destinationOut)
            }

            animatedFill(phase: phase)
        }
    }

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: weight))
            .symbolRenderingMode(.monochrome)
    }

    private func animatedFill(phase: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(baseColor)

            LinearGradient(
                stops: [
                    .init(color: baseColor.opacity(0.10), location: 0),
                    .init(color: softHighlightColor.opacity(0.42), location: 0.38),
                    .init(color: brightHighlightColor.opacity(0.72), location: 0.5),
                    .init(color: softHighlightColor.opacity(0.42), location: 0.62),
                    .init(color: baseColor.opacity(0.10), location: 1)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(width: frameWidth, height: gradientHeight)
            .offset(y: (0.5 - phase) * gradientHeight)
            .blendMode(.screen)
        }
        .mask(glyph.foregroundStyle(.white))
    }

    private static func animationPhase(at date: Date) -> CGFloat {
        let rawPhase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: animationDuration) / animationDuration
        return CGFloat(rawPhase)
    }
}
