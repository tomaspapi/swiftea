import AppKit
import SwiftUI

struct TemperatureSummaryCard: View {
    @Bindable var model: AppModel

    private enum StatusPresentation: Equatable {
        case heating
        case idle
        case empty
    }

    private var statusPresentation: StatusPresentation {
        if model.isEmpty == true {
            return .empty
        }

        return model.isTemperatureControlOff ? .idle : .heating
    }

    private var currentTemperatureDisplayLabel: String {
        statusPresentation == .empty ? "—" : model.currentTemperatureLabel
    }

    var body: some View {
        DashboardCard {
            cardContent
        }
            .animation(.snappy(duration: 0.34, extraBounce: 0.05), value: statusPresentation)
    }

    private var cardContent: some View {
        VStack(spacing: 5) {
            sectionTitle("Current temperature")

            Text(currentTemperatureDisplayLabel)
                .font(.system(size: 60, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .center)

            statusSymbol
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    private var titleColor: Color {
        .secondary
    }

    private var valueColor: Color {
        .primary
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch statusPresentation {
        case .heating:
            RepeatingHeatWavesSymbol()
                .frame(width: 22, height: 18)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.82).combined(with: .opacity),
                        removal: .scale(scale: 0.78).combined(with: .opacity)
                    )
                )
        case .idle:
            Image(systemName: "pause.fill")
                .font(.system(size: 14, weight: .semibold))
                .swifteaSymbolStyle(SwifteaSymbolColor.muted)
        case .empty:
            Text("Mug is currently empty")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(nsColor: .disabledControlTextColor))
                .lineLimit(1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(titleColor)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct RepeatingHeatWavesSymbol: NSViewRepresentable {
    func makeNSView(context: Context) -> RepeatingDrawOnImageView {
        RepeatingDrawOnImageView()
    }

    func updateNSView(_ nsView: RepeatingDrawOnImageView, context: Context) {}
}

private final class RepeatingDrawOnImageView: NSImageView {
    private var isEffectActive = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: 22, height: 18)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        image = NSImage(
            systemSymbolName: "heat.waves",
            accessibilityDescription: "Heating"
        )
        symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 14,
            weight: .semibold
        ).applying(.preferringMonochrome())
        contentTintColor = .systemOrange
        imageAlignment = .alignCenter
        imageScaling = .scaleProportionallyDown
        setAccessibilityLabel("Heating")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeAllSymbolEffects(animated: false)
            isEffectActive = false
        } else if !isEffectActive {
            addSymbolEffect(
                .drawOn.byLayer,
                options: .repeat(.periodic(delay: 1.0))
            )
            isEffectActive = true
        }
    }
}

#Preview {
    TemperatureSummaryCard(model: AppModel.previewConnected())
        .padding()
}
