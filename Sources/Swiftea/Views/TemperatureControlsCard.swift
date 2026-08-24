import SwiftUI

struct TemperatureControlsCard: View {
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

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Target temperature")
                        .font(.headline)

                    Spacer()

                    HStack(spacing: 12) {
                        Text("Heating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Toggle("", isOn: heatingBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!model.canAdjustTemperature)
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        model.decreaseTemperatureDraft()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 20, weight: .medium))
                            .swifteaSymbolStyle()
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canAdjustTemperature)

                    Spacer()

                    Text(model.targetTemperatureLabel)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Button {
                        model.increaseTemperatureDraft()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .swifteaSymbolStyle()
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canAdjustTemperature)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

#Preview {
    TemperatureControlsCard(model: AppModel.previewConnected())
        .padding()
}
