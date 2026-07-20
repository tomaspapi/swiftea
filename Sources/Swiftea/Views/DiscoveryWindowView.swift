import AppKit
import SwiftUI

struct DiscoveryWindowView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Searching for nearby mugs…")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)

            DiscoveryInstructions()

            ZStack {
                RadarScanView()
                    .frame(width: 280, height: 280)
                    .opacity(0.72)

                if !model.discoveryWindowMugs.isEmpty {
                    DiscoveryMugStack(mugs: model.discoveryWindowMugs) { mug in
                        model.connectDiscoveryMug(identifier: mug.identifier)
                        dismiss()
                        returnToMainWindow()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                .spring(response: 0.34, dampingFraction: 0.82),
                value: model.discoveryWindowMugs.map(\.identifier)
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: 420, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.beginDiscoveryWindow()
        }
        .onDisappear {
            model.endDiscoveryWindow()
        }
    }

    private func returnToMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindow = NSApp.windows.first { window in
            window.title == "Swiftea"
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct DiscoveryInstructions: View {
    private let steps = [
        "Hard close every app that regularly controls your Ember Mug, on every device.",
        "Press and hold the power button on the base of your mug for 6–8 seconds, until its light blinks blue.",
        "Your mug will appear on the discovery screen below."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(index + 1).")
                        .fontWeight(.semibold)
                        .frame(width: 16, alignment: .trailing)

                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 340, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How to prepare your mug for discovery")
    }
}

private struct DiscoveryMugStack: View {
    private static let maximumCenteredCards = 3
    private static let cardSpacing: CGFloat = 12
    private static let scrollViewportHeight: CGFloat = 376
    private static let fallbackCardHeight: CGFloat = 112

    let mugs: [AppModel.DiscoveryMugItem]
    let connect: (AppModel.DiscoveryMugItem) -> Void
    @State private var measuredCardHeight = Self.fallbackCardHeight

    var body: some View {
        ScrollView(.vertical) {
            cardStack
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity)
                .background(OverlayScrollViewConfigurator(isScrollable: isScrollable))
        }
        .frame(height: Self.scrollViewportHeight)
        .scrollDisabled(!isScrollable)
    }

    private var isScrollable: Bool {
        mugs.count > Self.maximumCenteredCards
    }

    private var topPadding: CGFloat {
        let visibleCount = min(max(mugs.count, 1), Self.maximumCenteredCards)
        let centeredStackHeight = CGFloat(visibleCount) * measuredCardHeight
            + CGFloat(max(visibleCount - 1, 0)) * Self.cardSpacing
        return max((Self.scrollViewportHeight - centeredStackHeight) / 2, 16)
    }

    private var bottomPadding: CGFloat {
        isScrollable ? 16 : topPadding
    }

    private func measureCardHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        guard abs(measuredCardHeight - height) > 0.5 else { return }
        measuredCardHeight = height
    }

    private var cardHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    measureCardHeight(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, newHeight in
                    measureCardHeight(newHeight)
                }
        }
    }

    private var cardStack: some View {
        GlassEffectContainer {
            VStack(spacing: Self.cardSpacing) {
                ForEach(mugs) { mug in
                    DiscoveryMugCard(mug: mug) {
                        connect(mug)
                    }
                    .background(cardHeightReader)
                    .transition(
                        .opacity
                            .combined(with: .scale(scale: 0.96))
                            .combined(with: .move(edge: .bottom))
                    )
                }
            }
        }
    }
}

private struct OverlayScrollViewConfigurator: NSViewRepresentable {
    let isScrollable: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureScrollView(from: nsView)
        }
    }

    private func configureScrollView(from nsView: NSView) {
        guard let scrollView = nsView.enclosingScrollView else { return }

        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = !isScrollable
        scrollView.drawsBackground = false
        scrollView.verticalScroller?.alphaValue = isScrollable ? 1 : 0
    }
}

private struct DiscoveryMugCard: View {
    let mug: AppModel.DiscoveryMugItem
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(mug.name)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Text(mug.metadata)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Button("Connect") {
                connect()
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(width: 190)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RadarScanView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 240.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4

            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let drawingInset: CGFloat = 6
                let radius = max(0, min(size.width, size.height) / 2 - drawingInset)
                let scanColor = Color(red: 0.34, green: 0.78, blue: 0.45)

                for ring in 1 ... 4 {
                    let ringRadius = radius * CGFloat(ring) / 4
                    let rect = CGRect(
                        x: center.x - ringRadius,
                        y: center.y - ringRadius,
                        width: ringRadius * 2,
                        height: ringRadius * 2
                    )

                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.secondary.opacity(0.08)),
                        lineWidth: 3
                    )
                }

                var rotatingContext = context
                rotatingContext.translateBy(x: center.x, y: center.y)
                rotatingContext.rotate(by: .degrees(phase * 360))

                let trailDegrees = 58.0
                let trailStop = CGFloat(trailDegrees / 360.0)
                var trail = Path()
                trail.move(to: .zero)
                trail.addArc(
                    center: .zero,
                    radius: radius,
                    startAngle: .degrees(-trailDegrees),
                    endAngle: .degrees(0),
                    clockwise: false
                )
                trail.closeSubpath()
                rotatingContext.fill(
                    trail,
                    with: .conicGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: scanColor.opacity(0.03), location: 0.045),
                            .init(color: scanColor.opacity(0.09), location: 0.095),
                            .init(color: scanColor.opacity(0.16), location: 0.135),
                            .init(color: scanColor.opacity(0.22), location: trailStop),
                            .init(color: .clear, location: trailStop + 0.001),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .zero,
                        angle: .degrees(-trailDegrees)
                    )
                )

                var beam = Path()
                beam.move(to: .zero)
                beam.addLine(to: CGPoint(x: radius, y: 0))
                rotatingContext.stroke(
                    beam,
                    with: .linearGradient(
                        Gradient(colors: [.clear, scanColor.opacity(0.42)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: radius, y: 0)
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .butt)
                )

                let centerDot = CGRect(
                    x: center.x - 3,
                    y: center.y - 3,
                    width: 6,
                    height: 6
                )
                context.fill(
                    Path(ellipseIn: centerDot),
                    with: .color(.secondary.opacity(0.12))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    DiscoveryWindowView(model: AppModel.previewConnected())
}
