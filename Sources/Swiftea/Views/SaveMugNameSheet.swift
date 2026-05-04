import SwiftUI

struct SaveMugNameSheet: View {
    @Bindable var model: AppModel
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.mugNameSheetTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Give this mug a name that Swiftea should remember on this Mac. The next time it appears, Swiftea will use your saved name instead of the generic Bluetooth name.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Saved name")
                    .font(.headline)

                TextField("Kitchen mug", text: $model.mugNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .onSubmit {
                        if model.canCommitMugNameDraft {
                            model.saveCurrentMugName()
                        }
                    }
            }

            if model.shouldShowHardwareDeviceName {
                LabeledContent("Hardware name", value: model.hardwareDeviceNameLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Cancel") {
                    model.cancelEditingCurrentMugName()
                }

                Button("Save") {
                    model.saveCurrentMugName()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCommitMugNameDraft)
            }
        }
        .padding(24)
        .frame(width: 460, height: 250, alignment: .topLeading)
        .onAppear {
            isNameFieldFocused = true
        }
    }
}

#Preview {
    let model = AppModel.previewConnected()
    model.isPresentingMugNameSheet = true
    model.mugNameDraft = "Desk mug"
    return SaveMugNameSheet(model: model)
}
