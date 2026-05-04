import AppKit
import SwiftUI

@main
struct SwifteaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updateController = UpdateController()
    @State private var model = AppModel.launchModel()

    var body: some Scene {
        WindowGroup("Swiftea", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                    AppLocationSynchronizer(preference: model.appLocationPreference)
                }
                .onAppear {
                    appDelegate.configure(model: model)
                }
                .frame(minWidth: 550, idealWidth: 550, maxWidth: 550, minHeight: 581, idealHeight: 581, maxHeight: 581)
        }
        .defaultSize(width: 550, height: 581)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updateController.updater)
            }
        }

        MenuBarExtra(isInserted: menuBarExtraBinding) {
            MenuBarStatusMenu(model: model)
        } label: {
            MenuBarStatusLabel(status: model.menuBarStatusTemperatureLabel)
        }
        .menuBarExtraStyle(.menu)

        Window("Discovery", id: "discovery") {
            DiscoveryWindowView(model: model)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 420, height: 460)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea Acknowledgements", id: "acknowledgements") {
            AcknowledgementsView()
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 520, height: 400)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea License", id: "license") {
            LicenseView()
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 520, height: 360)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("What’s New in Swiftea", id: "whats-new") {
            UpdateChangelogView()
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 480, height: 260)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model, updateController: updateController)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                    AppLocationSynchronizer(preference: model.appLocationPreference)
                }
        }
    }

    private var menuBarExtraBinding: Binding<Bool> {
        Binding(
            get: {
                model.appLocationPreference.includesMenuBar
            },
            set: { isInserted in
                guard !isInserted else { return }

                switch model.appLocationPreference {
                case .dockAndMenuBar:
                    model.appLocationPreference = .dock
                case .menuBar:
                    model.appLocationPreference = .dock
                case .dock:
                    break
                }
            }
        )
    }
}

private struct AppLocationSynchronizer: NSViewRepresentable {
    let preference: AppModel.AppLocationPreference

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyActivationPolicy()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyActivationPolicy()
    }

    private func applyActivationPolicy() {
        DispatchQueue.main.async {
            guard NSApp.activationPolicy() != preference.activationPolicy else { return }
            NSApp.setActivationPolicy(preference.activationPolicy)
        }
    }
}

private struct MenuBarStatusLabel: View {
    let status: String?

    var body: some View {
        if let status {
            HStack(spacing: 3) {
                Image(systemName: "mug.fill")
                Text(status)
            }
        } else {
            Image(systemName: "mug")
        }
    }
}

private struct MenuBarStatusMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let currentMug = model.currentSidebarMug, model.shouldShowMugDashboard {
            Text(currentMug.name)
            Text(model.menuBarCurrentTemperatureLine)
                .foregroundStyle(.secondary)
            Text(model.menuBarTargetTemperatureLine)
                .foregroundStyle(.secondary)
            Text(model.menuBarBatteryLine)
                .foregroundStyle(.secondary)
            Divider()
        }

        Button("Show Swiftea") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Swiftea") {
            NSApp.terminate(nil)
        }
    }
}

private extension AppModel.ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
