import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            MugSidebarView(
                model: model,
                selection: Binding(
                    get: { model.selectedMugIdentifier },
                    set: { identifier in
                        if let identifier {
                            model.selectSidebarMug(identifier: identifier)
                        }
                    }
                )
            )
        } detail: {
            if model.shouldShowMugDashboard {
                MugDashboardView(model: model)
            } else {
                EmptyMugDashboardView()
            }
        }
        .onAppear {
            model.selectDefaultSidebarMugIfNeeded()

            if model.consumeUpdateChangelogPresentation() {
                openWindow(id: "whats-new")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .toolbar {
            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help("Settings")

                Button {
                    openWindow(id: "discovery")
                } label: {
                    Label("Discover New Mug", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("Discover New Mug")
                .disabled(!model.canOpenDiscoveryWindow)
            }
        }
        .sheet(isPresented: $model.isPresentingMugNameSheet) {
            SaveMugNameSheet(model: model)
        }
    }
}

private struct EmptyMugDashboardView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mug.fill")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.tertiary)

            Text("Connect to a mug to get started")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(model: AppModel.previewConnected())
        .frame(width: 1024, height: 720)
}
