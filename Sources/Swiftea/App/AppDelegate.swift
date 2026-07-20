import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?

    func configure(model: AppModel) {
        self.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applySavedActivationPolicy()
        applyBundledAppIcon()

        guard ProcessInfo.processInfo.environment["SWIFTEA_ACTIVATE_ON_LAUNCH"] == "1" else {
            return
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard let model else { return false }
        return !model.keepsRunningWhenWindowClosed
    }

    private func applyBundledAppIcon() {
        guard
            let iconImage = Self.bundledAppIcon()
        else {
            return
        }

        NSApp.applicationIconImage = iconImage
    }

    private func applySavedActivationPolicy() {
        let savedPreference = UserDefaults.standard.string(forKey: AppPreferencesKey.appLocationPreference)
        let preference = savedPreference.flatMap(AppModel.AppLocationPreference.init(rawValue:)) ?? .dockAndMenuBar
        NSApp.setActivationPolicy(preference.activationPolicy)
    }
}

private extension AppDelegate {
    static func bundledAppIcon() -> NSImage? {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        else {
            return nil
        }

        return NSImage(contentsOf: iconURL)
    }
}
