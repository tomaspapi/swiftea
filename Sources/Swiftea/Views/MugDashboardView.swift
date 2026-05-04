import AppKit
import SwiftUI

struct MugDashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(spacing: 16) {
                    HeatingControlCard(model: model)

                    TemperatureSummaryCard(model: model)

                    HistoryChartCard(model: model)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 16) {
                Text(model.deviceName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 16)

                BatteryStatusIndicator(
                    model: model,
                    size: 29
                )
                .padding(.top, 2)
            }

            if let specificationLabel = model.currentMugSpecificationLabel {
                Text(specificationLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let serialNumber = model.deviceSerialNumber {
                Button {
                    copySerialNumberToClipboard(serialNumber)
                } label: {
                    Text("S/N: \(serialNumber)")
                        .font(.caption.weight(.semibold))
                        .monospaced()
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Copy serial number")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copySerialNumberToClipboard(_ serialNumber: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(serialNumber, forType: .string)
    }
}

#Preview {
    MugDashboardView(model: AppModel.previewConnected())
        .frame(width: 760, height: 700)
}
