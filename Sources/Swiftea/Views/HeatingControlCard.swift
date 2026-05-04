import AppKit
import SwiftUI

struct HeatingControlCard: View {
    @Bindable var model: AppModel

    private var heatingBinding: Binding<Bool> {
        Binding(
            get: { !model.isTemperatureControlOff },
            set: { model.setTemperatureControlEnabled($0) }
        )
    }

    private var isTargetControlEnabled: Bool {
        model.canAdjustTemperature && !model.isTemperatureControlOff
    }

    private var canDecreaseTargetTemperature: Bool {
        isTargetControlEnabled && model.canDecreaseTargetTemperatureDraft
    }

    private var canIncreaseTargetTemperature: Bool {
        isTargetControlEnabled && model.canIncreaseTargetTemperatureDraft
    }

    private var targetTemperatureLabelColor: Color {
        model.isTemperatureControlOff ? Color(nsColor: .disabledControlTextColor) : .primary
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                HeatingSettingsRow {
                    Text("Heating")
                        .font(.body)
                } trailing: {
                    Toggle("", isOn: heatingBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!model.canAdjustTemperature)
                }

                Divider()
                    .padding(.horizontal, 12)

                HeatingSettingsRow {
                    Text("Target temperature")
                        .font(.body)
                        .foregroundStyle(targetTemperatureLabelColor)
                } trailing: {
                    TemperatureSegmentedControl(
                        valueLabel: model.targetTemperatureLabel,
                        isEnabled: isTargetControlEnabled,
                        canDecrement: canDecreaseTargetTemperature,
                        canIncrement: canIncreaseTargetTemperature,
                        onDecrement: model.decreaseTemperatureDraft,
                        onIncrement: model.increaseTemperatureDraft
                    )
                    .frame(width: 104, height: 20)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .alert("The mug is currently empty", isPresented: $model.isPresentingEmptyHeatingAlert) {
            Button("Turn On") {
                model.confirmEmptyHeatingAlert()
            }

            Button("Cancel", role: .cancel) {
                model.cancelEmptyHeatingAlert()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Are you sure you want to turn heating on?")
        }
    }
}

private struct HeatingSettingsRow<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading

            Spacer(minLength: 12)

            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
    }
}

private struct TemperatureSegmentedControl: NSViewRepresentable {
    private static let sideSegmentWidth: CGFloat = 24
    private static let valueSegmentWidth: CGFloat = 56

    let valueLabel: String
    let isEnabled: Bool
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDecrement: onDecrement, onIncrement: onIncrement)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: segmentLabels(),
            trackingMode: .momentary,
            target: context.coordinator,
            action: #selector(Coordinator.handleSegmentChange(_:))
        )
        control.segmentStyle = .automatic
        control.controlSize = .small
        control.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        control.setWidth(Self.sideSegmentWidth, forSegment: 0)
        control.setWidth(Self.valueSegmentWidth, forSegment: 1)
        control.setWidth(Self.sideSegmentWidth, forSegment: 2)
        applySegmentEnabledState(to: control)
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        context.coordinator.onDecrement = onDecrement
        context.coordinator.onIncrement = onIncrement
        let labels = segmentLabels()
        nsView.setLabel(labels[0], forSegment: 0)
        nsView.setLabel(labels[1], forSegment: 1)
        nsView.setLabel(labels[2], forSegment: 2)
        applySegmentEnabledState(to: nsView)
    }

    private func applySegmentEnabledState(to control: NSSegmentedControl) {
        control.setEnabled(canDecrement, forSegment: 0)
        control.setEnabled(isEnabled, forSegment: 1)
        control.setEnabled(canIncrement, forSegment: 2)
    }

    private func segmentLabels() -> [String] {
        ["−", valueLabel, "+"]
    }

    final class Coordinator: NSObject {
        var onDecrement: () -> Void
        var onIncrement: () -> Void

        init(onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) {
            self.onDecrement = onDecrement
            self.onIncrement = onIncrement
        }

        @MainActor
        @objc func handleSegmentChange(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0:
                onDecrement()
            case 2:
                onIncrement()
            default:
                return
            }

            sender.selectedSegment = -1
        }
    }
}

#Preview {
    HeatingControlCard(model: AppModel.previewConnected())
        .padding()
}
