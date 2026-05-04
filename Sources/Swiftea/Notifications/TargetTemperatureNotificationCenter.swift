import Foundation
import UserNotifications

@MainActor
protocol TargetTemperatureNotificationDelivering: AnyObject {
    func requestAuthorizationIfNeeded() async -> Bool
    func deliverTargetReachedNotification(mugName: String, targetLabel: String) async
    func deliverBatteryFullyChargedNotification(mugName: String) async
    func deliverBatteryFullyDischargedNotification(mugName: String) async
}

@MainActor
final class NativeTargetTemperatureNotificationCenter: NSObject, TargetTemperatureNotificationDelivering, UNUserNotificationCenterDelegate {
    static let shared = NativeTargetTemperatureNotificationCenter()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func deliverTargetReachedNotification(mugName: String, targetLabel: String) async {
        await deliverNotification(
            identifierPrefix: "swiftea.target-temperature",
            mugName: mugName,
            body: "Your drink is ready at \(targetLabel)"
        )
    }

    func deliverBatteryFullyChargedNotification(mugName: String) async {
        await deliverNotification(
            identifierPrefix: "swiftea.battery.fully-charged",
            mugName: mugName,
            body: "Your mug fully charged to 100%"
        )
    }

    func deliverBatteryFullyDischargedNotification(mugName: String) async {
        await deliverNotification(
            identifierPrefix: "swiftea.battery.fully-discharged",
            mugName: mugName,
            body: "Your mug is fully discharged at 0%"
        )
    }

    private func deliverNotification(identifierPrefix: String, mugName: String, body: String) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = mugName
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class SilentTargetTemperatureNotificationCenter: TargetTemperatureNotificationDelivering {
    static let shared = SilentTargetTemperatureNotificationCenter()

    func requestAuthorizationIfNeeded() async -> Bool {
        true
    }

    func deliverTargetReachedNotification(mugName: String, targetLabel: String) async {}

    func deliverBatteryFullyChargedNotification(mugName: String) async {}

    func deliverBatteryFullyDischargedNotification(mugName: String) async {}
}
