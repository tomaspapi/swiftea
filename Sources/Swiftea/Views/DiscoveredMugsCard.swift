import SwiftUI

struct DiscoveredMugsCard: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Text(model.discoveredMugsSummary)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if model.hasSavedMugPreference {
                        Button("Forget Preferred Mug") {
                            model.forgetSavedMug()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.discoveredMugs) { mug in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(mug.name)
                                        .font(.headline)

                                    if mug.identifier == model.preferredPeripheralIdentifier {
                                        Text("Preferred")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }

                                Text(mug.signalLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(mug.identifier == model.preferredPeripheralIdentifier ? "Connect Again" : "Connect") {
                                model.chooseDiscoveredMug(mug)
                            }
                            .buttonStyle(.glass)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } label: {
            Text("Nearby mugs")
        }
    }
}

#Preview {
    let model = AppModel.previewConnected()
    return DiscoveredMugsCard(model: model)
        .padding()
}
