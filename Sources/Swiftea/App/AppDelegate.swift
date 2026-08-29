import AppKit
import OSLog

enum MainWindowLifecycleState: String, Equatable {
    case opening
    case open
    case closed
}

struct MainWindowPresentationState: Equatable {
    private(set) var lifecycle: MainWindowLifecycleState = .opening
    private(set) var generation = 0
    private(set) var activationPending = false

    var requiresRegularActivationPolicy: Bool {
        lifecycle != .closed
    }

    mutating func requestPresentation() -> Int {
        generation += 1
        lifecycle = .opening
        activationPending = true
        return generation
    }

    mutating func registerWindow() -> (generation: Int, shouldActivate: Bool)? {
        guard lifecycle != .closed else { return nil }
        lifecycle = .open
        return (generation, activationPending)
    }

    mutating func completePresentation(generation expectedGeneration: Int) -> Bool {
        guard generation == expectedGeneration, lifecycle != .closed else { return false }
        lifecycle = .open
        activationPending = false
        return true
    }

    mutating func closeWindow() -> Int {
        generation += 1
        lifecycle = .closed
        activationPending = false
        return generation
    }

    func shouldApplyClose(generation expectedGeneration: Int) -> Bool {
        generation == expectedGeneration && lifecycle == .closed
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private weak var registeredMainWindow: NSWindow?
    private var configuredLocationPreference: AppModel.AppLocationPreference?
    private var presentationState = MainWindowPresentationState()
    private var scheduledPresentationGeneration: Int?

    func configure(model: AppModel) {
        self.model = model
        updateAppLocationPreference(model.appLocationPreference)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setActivationPolicy(.regular, reason: "application launch")
        applyBundledAppIcon()
        installWindowCloseObserver()

        guard ProcessInfo.processInfo.environment["SWIFTEA_ACTIVATE_ON_LAUNCH"] == "1" else {
            return
        }

        _ = requestMainWindowPresentation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: nil
        )
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

    func updateAppLocationPreference(_ preference: AppModel.AppLocationPreference) {
        configuredLocationPreference = preference
        synchronizeActivationPolicy(reason: "location preference changed")
    }

    @discardableResult
    func requestMainWindowPresentation() -> Bool {
        let generation = presentationState.requestPresentation()
        AppLog.windowing.notice(
            "Main window presentation requested generation=\(generation, privacy: .public)"
        )
        setActivationPolicy(.regular, reason: "main window presentation requested")

        guard let window = registeredMainWindow ?? NSApp.windows.first(where: \.isSwifteaMainWindow) else {
            return false
        }

        registeredMainWindow = window
        schedulePresentation(of: window, generation: generation)
        return true
    }

    func registerMainWindow(_ window: NSWindow) {
        guard let registration = presentationState.registerWindow() else {
            AppLog.windowing.debug("Ignored registration from a closed main-window generation")
            return
        }

        registeredMainWindow = window
        setActivationPolicy(.regular, reason: "main window registered")
        AppLog.windowing.notice(
            "Main window registered generation=\(registration.generation, privacy: .public) activationPending=\(registration.shouldActivate, privacy: .public)"
        )

        if registration.shouldActivate {
            schedulePresentation(of: window, generation: registration.generation)
        }
    }

    private func schedulePresentation(of window: NSWindow, generation: Int) {
        guard scheduledPresentationGeneration != generation else { return }
        scheduledPresentationGeneration = generation

        // Changing from accessory to regular and claiming app activation are separate
        // AppKit lifecycle transitions. Present on the next run-loop turn so the
        // regular policy is established before the app requests the menu bar.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.present(window, generation: generation)
        }
    }

    private func present(_ window: NSWindow, generation: Int) {
        if scheduledPresentationGeneration == generation {
            scheduledPresentationGeneration = nil
        }

        guard presentationState.completePresentation(generation: generation) else {
            AppLog.windowing.debug(
                "Ignored stale main window presentation generation=\(generation, privacy: .public)"
            )
            return
        }

        registeredMainWindow = window
        setActivationPolicy(.regular, reason: "presenting main window")
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        let runningApplicationActivated = NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate()
        AppLog.windowing.notice(
            "Main window activation requested generation=\(generation, privacy: .public) runningApplicationAccepted=\(runningApplicationActivated, privacy: .public)"
        )

        DispatchQueue.main.async {
            AppLog.windowing.notice(
                "Main window activation settled active=\(NSApp.isActive, privacy: .public) ownsMenuBar=\(NSRunningApplication.current.ownsMenuBar, privacy: .public) policy=\(NSApp.activationPolicy().rawValue, privacy: .public)"
            )
        }
    }

    private func installWindowCloseObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window.isSwifteaMainWindow else { return }

        registeredMainWindow = nil
        scheduledPresentationGeneration = nil
        let closeGeneration = presentationState.closeWindow()
        AppLog.windowing.notice(
            "Main window closed generation=\(closeGeneration, privacy: .public)"
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.presentationState.shouldApplyClose(generation: closeGeneration) else {
                AppLog.windowing.debug(
                    "Ignored stale main window close generation=\(closeGeneration, privacy: .public)"
                )
                return
            }

            if self.model?.keepsRunningWhenWindowClosed == false {
                NSApp.terminate(nil)
            } else {
                self.synchronizeActivationPolicy(reason: "main window closed")
            }
        }
    }

    private var currentLocationPreference: AppModel.AppLocationPreference {
        if let configuredLocationPreference {
            return configuredLocationPreference
        }

        if let model {
            return model.appLocationPreference
        }

        let savedValue = UserDefaults.standard.string(forKey: AppPreferencesKey.appLocationPreference)
        return savedValue.flatMap(AppModel.AppLocationPreference.init(rawValue:)) ?? .dockAndMenuBar
    }

    private func synchronizeActivationPolicy(reason: String) {
        let policy = currentLocationPreference.activationPolicy(
            mainWindowIsPresented: presentationState.requiresRegularActivationPolicy
        )
        setActivationPolicy(policy, reason: reason)
    }

    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy, reason: String) {
        guard NSApp.activationPolicy() != policy else { return }
        let accepted = NSApp.setActivationPolicy(policy)
        AppLog.windowing.notice(
            "Activation policy requested policy=\(policy.rawValue, privacy: .public) accepted=\(accepted, privacy: .public) reason=\(reason, privacy: .public) lifecycle=\(self.presentationState.lifecycle.rawValue, privacy: .public)"
        )
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
