import SwiftUI

struct MugSidebarView: View {
    @Bindable var model: AppModel
    @Binding var selection: String?
    @State private var pendingForgetMug: AppModel.SidebarMugItem?

    var body: some View {
        List(selection: $selection) {
            if !model.connectedSidebarMugs.isEmpty {
                Section("Connected Mugs") {
                    ForEach(model.connectedSidebarMugs) { mug in
                        sidebarRow(for: mug)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                model.beginEditingSidebarMugName(identifier: mug.identifier)
                            })
                            .contextMenu {
                                sidebarContextMenu(for: mug)
                            }
                            .tag(mug.identifier)
                    }
                }
            }

            if !model.savedSidebarMugs.isEmpty {
                Section("Saved Mugs") {
                    ForEach(model.savedSidebarMugs) { mug in
                        sidebarRow(for: mug)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                model.beginEditingSidebarMugName(identifier: mug.identifier)
                            })
                            .contextMenu {
                                sidebarContextMenu(for: mug)
                            }
                            .tag(mug.identifier)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
        .alert(
            "Forget \(pendingForgetMug?.name ?? "this mug")?",
            isPresented: Binding(
                get: { pendingForgetMug != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingForgetMug = nil
                    }
                }
            ),
            presenting: pendingForgetMug
        ) { mug in
            Button("Forget", role: .destructive) {
                model.forgetSidebarMug(identifier: mug.identifier)
                pendingForgetMug = nil
            }
            Button("Cancel", role: .cancel) {
                pendingForgetMug = nil
            }
        } message: { mug in
            Text("Swiftea will remove \(mug.name) and you will need to pair it again next time.")
        }
    }

    private func sidebarRow(for mug: AppModel.SidebarMugItem) -> some View {
        MugSidebarRow(
            mug: mug,
            nameDraft: Binding(
                get: { model.sidebarMugNameDraft },
                set: { model.sidebarMugNameDraft = $0 }
            ),
            isEditingName: model.sidebarMugNameEditingIdentifier == mug.identifier,
            commitRename: {
                model.commitSidebarMugNameRename()
            },
            cancelRename: {
                model.cancelSidebarMugNameRename()
            }
        )
    }

    @ViewBuilder
    private func sidebarContextMenu(for mug: AppModel.SidebarMugItem) -> some View {
        if mug.isConnected {
            Button("Disconnect") {
                model.disconnectSidebarMug(identifier: mug.identifier)
            }
        } else {
            Button("Connect") {
                model.connectSidebarMug(identifier: mug.identifier)
            }
            .disabled(!model.canConnectSidebarMug(identifier: mug.identifier))
        }

        Button("Rename") {
            model.beginEditingSidebarMugName(identifier: mug.identifier)
        }

        Toggle("Connect on launch", isOn: Binding(
            get: {
                model.isAutoConnectEnabled(for: mug.identifier)
            },
            set: { isEnabled in
                model.setAutoConnectEnabled(isEnabled, for: mug.identifier)
            }
        ))
        .disabled(!model.canEnableAutoConnect(for: mug.identifier))

        Divider()

        Button("Forget", role: .destructive) {
            pendingForgetMug = mug
        }
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var selection: String? = "PREVIEW-MUG"
        @State private var model = AppModel.previewConnected()

        var body: some View {
            MugSidebarView(model: model, selection: $selection)
                .frame(width: 220, height: 640)
        }
    }

    return PreviewHost()
}
