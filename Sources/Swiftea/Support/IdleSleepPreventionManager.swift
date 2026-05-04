import Foundation

@MainActor
protocol IdleSleepPreventionManaging: AnyObject {
    func setIdleSleepPreventionEnabled(_ isEnabled: Bool)
}

@MainActor
final class NativeIdleSleepPreventionManager: IdleSleepPreventionManaging {
    static let shared = NativeIdleSleepPreventionManager()

    private var activity: NSObjectProtocol?

    private init() {}

    func setIdleSleepPreventionEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard activity == nil else { return }

            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Swiftea is connected to a mug and logging live battery and temperature readings."
            )
            AppLog.power.info("Idle system sleep prevention enabled while a mug is connected.")
        } else {
            guard let existingActivity = activity else { return }

            ProcessInfo.processInfo.endActivity(existingActivity)
            activity = nil
            AppLog.power.info("Idle system sleep prevention disabled because no mugs are connected.")
        }
    }
}

@MainActor
final class NoOpIdleSleepPreventionManager: IdleSleepPreventionManaging {
    static let shared = NoOpIdleSleepPreventionManager()

    private init() {}

    func setIdleSleepPreventionEnabled(_ isEnabled: Bool) {}
}
