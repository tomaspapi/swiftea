import SwiftUI

struct SessionDiagnosticsCard: View {
    @Bindable var model: AppModel
    @State private var isExpanded = false

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        StateDetailRow(title: "Bluetooth ID", value: privateDiagnosticValue(for: model.bluetoothIdentifierLabel))
                        StateDetailRow(title: "Serial number", value: privateDiagnosticValue(for: model.serialNumberLabel))
                        StateDetailRow(title: "Current temperature path", value: model.currentTemperaturePathLabel)
                        StateDetailRow(title: "Target temperature path", value: model.targetTemperaturePathLabel)
                        StateDetailRow(title: "Battery path", value: model.batteryPathLabel)
                        StateDetailRow(title: "Contents path", value: model.contentsPathLabel)
                        StateDetailRow(title: "Last live reading", value: model.lastReadingAtLabel)
                        StateDetailRow(title: "Last target change", value: model.lastTargetWriteAtLabel)
                    }
                }
                .padding(.top, 2)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session diagnostics")
                        .font(.headline)

                    Text(model.lastDiscoveryDetail)
                        .foregroundStyle(.secondary)

                    Text("Low-level device details for troubleshooting.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func privateDiagnosticValue(for value: String) -> String {
        value == "Unavailable" ? value : "Hidden"
    }
}

#Preview {
    SessionDiagnosticsCard(model: AppModel.previewConnected())
        .padding()
}
