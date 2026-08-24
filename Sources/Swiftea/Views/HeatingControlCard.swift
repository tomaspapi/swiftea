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

    private var emptyHeatingAlertBinding: Binding<Bool> {
        Binding(
            get: { model.emptyHeatingAlertPresentation == .mainWindow },
            set: { isPresented in
                if !isPresented {
                    model.cancelEmptyHeatingAlert()
                }
            }
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
        DashboardCard {
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

                HeatingSettingsRow(contentOffsetY: -1) {
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
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .alert("The mug is currently empty", isPresented: emptyHeatingAlertBinding) {
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
    private let contentOffsetY: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        contentOffsetY: CGFloat = 0,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.contentOffsetY = contentOffsetY
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading

            Spacer(minLength: 12)

            trailing
        }
        .offset(y: contentOffsetY)
        .frame(minHeight: 42)
        .padding(.horizontal, 12)
    }
}

#Preview {
    HeatingControlCard(model: AppModel.previewConnected())
        .padding()
}
