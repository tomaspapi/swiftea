import SwiftUI

struct BatteryStatusIndicator: View {
    let model: AppModel
    var size: CGFloat = 29

    private enum BatteryVisualState: Equatable {
        case unavailable
        case normal
        case caution
        case critical
        case charging
    }

    private var batteryNumberLabel: String {
        guard let batteryLevel = model.batteryLevel else {
            return "—"
        }

        return String(Int((batteryLevel * 100).rounded()))
    }

    private var visualState: BatteryVisualState {
        if model.isCharging {
            return .charging
        }

        guard let batteryLevel = model.batteryLevel else {
            return .unavailable
        }

        if batteryLevel <= 0.20 {
            return .critical
        }

        if batteryLevel <= 0.50 {
            return .caution
        }

        return .normal
    }

    private var tintRole: BatteryChargeGauge.TintRole {
        switch visualState {
        case .charging:
            return .charging
        case .critical:
            return .critical
        case .caution:
            return .caution
        case .unavailable:
            return .unavailable
        case .normal:
            return .normal
        }
    }

    var body: some View {
        BatteryChargeGauge(
            level: model.batteryFillFraction,
            label: batteryNumberLabel,
            tintRole: tintRole,
            isCharging: model.isCharging,
            accessibilityValue: model.batteryDetailLine,
            size: size
        )
        .animation(.snappy(duration: 0.45, extraBounce: 0.06), value: visualState)
        .animation(.smooth(duration: 0.35), value: model.batteryFillFraction)
        .contentShape(Rectangle())
        .help("Battery")
    }
}

private struct BatteryChargeGauge: View {
    enum TintRole: Equatable {
        case unavailable
        case normal
        case caution
        case critical
        case charging

        var color: Color {
            switch self {
            case .charging:
                return .green
            case .critical:
                return .red
            case .caution:
                return .yellow
            case .unavailable:
                return .secondary
            case .normal:
                return .primary
            }
        }
    }

    let level: Double
    let label: String
    let tintRole: TintRole
    let isCharging: Bool
    let accessibilityValue: String
    let size: CGFloat

    @State private var frontTintRole: TintRole
    @State private var backTintRole: TintRole?
    @State private var tintBlend = 1.0

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    private var targetTintRole: TintRole { tintRole }

    init(
        level: Double,
        label: String,
        tintRole: TintRole,
        isCharging: Bool,
        accessibilityValue: String,
        size: CGFloat
    ) {
        self.level = level
        self.label = label
        self.tintRole = tintRole
        self.isCharging = isCharging
        self.accessibilityValue = accessibilityValue
        self.size = size
        _frontTintRole = State(initialValue: tintRole)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary.opacity(0.22), lineWidth: ringLineWidth)

            if let backTintRole {
                BatteryRing(level: clampedLevel, color: backTintRole.color, lineWidth: ringLineWidth)
                    .opacity(1 - tintBlend)
            }

            BatteryRing(level: clampedLevel, color: frontTintRole.color, lineWidth: ringLineWidth)
                .opacity(tintBlend)

            ZStack {
                if let backTintRole {
                    batteryNumber(color: backTintRole.color)
                        .opacity(1 - tintBlend)
                }

                batteryNumber(color: frontTintRole.color)
                    .opacity(tintBlend)
            }
            if isCharging {
                chargingBolt
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                            removal: .scale(scale: 0.78).combined(with: .opacity)
                        )
                    )
            }
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .onChange(of: targetTintRole) { _, newValue in
            guard newValue != frontTintRole else { return }
            backTintRole = frontTintRole
            frontTintRole = newValue
            tintBlend = 0

            withAnimation(.easeInOut(duration: 0.42)) {
                tintBlend = 1
            }
        }
        .animation(.smooth(duration: 0.45), value: clampedLevel)
        .animation(.snappy(duration: 0.34, extraBounce: 0.05), value: isCharging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(accessibilityValue)
    }

    private var ringLineWidth: CGFloat {
        max(4.3, size * 0.15)
    }

    private var boltSize: CGFloat {
        size * 0.28
    }

    private var boltOutlineWidth: CGFloat {
        max(0.7, size * 0.02)
    }

    private var boltCutoutRadius: CGFloat {
        max(1.4, boltOutlineWidth * 2)
    }

    private var boltOffsetY: CGFloat {
        -(size * 0.5)
    }

    private var numberFontSize: CGFloat {
        let scale = isThreeDigitNumber ? 0.36 : 0.38
        return size * scale
    }

    private var isThreeDigitNumber: Bool {
        label.count == 3 && label.allSatisfy(\.isNumber)
    }

    @ViewBuilder
    private func batteryNumber(color: Color) -> some View {
        Text(label)
            .font(.system(size: numberFontSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .allowsTightening(true)
            .contentTransition(.numericText())
    }

    private var chargingBolt: some View {
        AnimatedStatusSymbol(
            systemName: "bolt.fill",
            fontSize: boltSize,
            weight: .semibold,
            baseColor: frontTintRole.color,
            softHighlightColor: Color(red: 0.70, green: 0.94, blue: 0.75),
            brightHighlightColor: Color(red: 0.82, green: 0.98, blue: 0.85),
            cutoutRadius: boltCutoutRadius
        )
        .offset(y: boltOffsetY)
        .accessibilityHidden(true)
    }
}

private struct BatteryRing: View {
    let level: Double
    let color: Color
    let lineWidth: CGFloat

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var body: some View {
        Circle()
            .trim(from: 0, to: clampedLevel)
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round
                )
            )
            .rotationEffect(.degrees(-90))
    }
}

#Preview {
    BatteryStatusIndicator(model: AppModel.previewConnected())
        .padding()
}
