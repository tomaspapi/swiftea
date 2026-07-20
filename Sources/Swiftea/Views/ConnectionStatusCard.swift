import SwiftUI

struct ConnectionStatusCard: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.connectionState.systemImage)
                        .font(.title2)
                        .swifteaSymbolStyle(SwifteaSymbolColor.blue)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.connectionState.title)
                            .font(.headline)

                        Text(model.statusMessage)
                            .foregroundStyle(.secondary)

                        LabeledContent("Device", value: model.deviceName)
                            .font(.subheadline)
                            .padding(.top, 4)

                        if model.shouldShowHardwareDeviceName {
                            LabeledContent("Hardware name", value: model.hardwareDeviceNameLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if model.canEditCurrentMugName {
                            HStack(spacing: 10) {
                                Button(model.currentMugNameActionTitle) {
                                    model.beginEditingCurrentMugName()
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)

                                if model.canRemoveCurrentMugName {
                                    Button("Remove Name") {
                                        model.removeCurrentMugName()
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }

                    Spacer()

                    if let actionTitle = model.connectionActionTitle {
                        Button(actionTitle) {
                            model.performConnectionAction()
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    StateDetailRow(title: "Bluetooth access", value: model.bluetoothAccessLabel)
                    StateDetailRow(title: "Bluetooth hardware", value: model.bluetoothHardwareLabel)
                    StateDetailRow(title: "Discovery", value: model.discoveryLabel)
                    StateDetailRow(title: "Last connection", value: model.lastConnectedAtLabel)
                }
            }
        } label: {
            Text("Connection")
        }
    }
}

#Preview {
    ConnectionStatusCard(model: AppModel.previewConnected())
        .padding()
}
