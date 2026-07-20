import SwiftUI

struct TemperatureSegmentedControl: View {
    @Environment(\.controlSize) private var controlSize

    let valueLabel: String
    let isEnabled: Bool
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    private var metrics: Metrics {
        Metrics(controlSize: controlSize, valueLabel: valueLabel)
    }

    var body: some View {
        HStack(spacing: 0) {
            temperatureButton(
                systemName: "minus",
                accessibilityLabel: "Decrease target temperature",
                isEnabled: canDecrement,
                symbolOffsetX: metrics.minusSymbolOffsetX,
                action: onDecrement
            )

            Text(valueLabel)
                .font(.system(size: metrics.valueFontSize, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? Color.primary : Color(nsColor: .disabledControlTextColor))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: metrics.valueWidth, height: metrics.height)
                .accessibilityLabel("Target temperature \(valueLabel)")

            temperatureButton(
                systemName: "plus",
                accessibilityLabel: "Increase target temperature",
                isEnabled: canIncrement,
                action: onIncrement
            )
        }
        .frame(height: metrics.height)
        .background(
            .quaternary,
            in: RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        )
        .fixedSize()
    }

    private func temperatureButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        symbolOffsetX: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: metrics.buttonFontSize, weight: .semibold, design: .default))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isEnabled ? Color.primary : Color(nsColor: .disabledControlTextColor))
                .symbolColorRenderingMode(.flat)
                .offset(x: symbolOffsetX)
                .frame(width: metrics.sideWidth, height: metrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct Metrics {
    let height: CGFloat
    let sideWidth: CGFloat
    let valueWidth: CGFloat
    let buttonFontSize: CGFloat
    let valueFontSize: CGFloat
    let minusSymbolOffsetX: CGFloat
    let cornerRadius: CGFloat

    init(controlSize: ControlSize, valueLabel: String) {
        let usesFahrenheitWidth = valueLabel.contains("°F")

        switch controlSize {
        case .mini:
            height = 16
            sideWidth = 24
            valueWidth = usesFahrenheitWidth ? 42 : 32
            buttonFontSize = 8
            valueFontSize = 10
            minusSymbolOffsetX = 0.75
            cornerRadius = 8
        case .small:
            height = 21.5
            sideWidth = 26
            valueWidth = usesFahrenheitWidth ? 48 : 38
            buttonFontSize = 8
            valueFontSize = 12
            minusSymbolOffsetX = 0.75
            cornerRadius = 10.75
        default:
            height = 34
            sideWidth = 36
            valueWidth = usesFahrenheitWidth ? 68 : 52
            buttonFontSize = 8
            valueFontSize = 16
            minusSymbolOffsetX = 0.75
            cornerRadius = 12
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        TemperatureSegmentedControl(
            valueLabel: "55°C",
            isEnabled: true,
            canDecrement: true,
            canIncrement: true,
            onDecrement: {},
            onIncrement: {}
        )
        .controlSize(.small)

        TemperatureSegmentedControl(
            valueLabel: "143°F",
            isEnabled: true,
            canDecrement: true,
            canIncrement: false,
            onDecrement: {},
            onIncrement: {}
        )
        .controlSize(.small)

        TemperatureSegmentedControl(
            valueLabel: "62°C",
            isEnabled: true,
            canDecrement: true,
            canIncrement: false,
            onDecrement: {},
            onIncrement: {}
        )
        .controlSize(.mini)

        TemperatureSegmentedControl(
            valueLabel: "143°F",
            isEnabled: true,
            canDecrement: true,
            canIncrement: false,
            onDecrement: {},
            onIncrement: {}
        )
        .controlSize(.mini)

        TemperatureSegmentedControl(
            valueLabel: "Off",
            isEnabled: false,
            canDecrement: false,
            canIncrement: false,
            onDecrement: {},
            onIncrement: {}
        )
        .controlSize(.small)
    }
    .padding()
}
