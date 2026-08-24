import Foundation

@MainActor
protocol AppPreferencesStore: AnyObject {
    func bool(forKey key: String) -> Bool?
    func double(forKey key: String) -> Double?
    func string(forKey key: String) -> String?
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

enum AppPreferencesKey {
    static let targetTemperatureDraftCelsius = "swiftea.targetTemperatureDraftCelsius"
    static let targetTemperatureDraftsByMug = "swiftea.targetTemperatureDraftsByMug"
    static let lastKnownDeviceName = "swiftea.lastKnownDeviceName"
    static let preferredPeripheralIdentifier = "swiftea.preferredPeripheralIdentifier"
    static let selectedMugIdentifier = "swiftea.selectedMugIdentifier"
    static let savedMugIdentifiers = "swiftea.savedMugIdentifiers"
    static let autoConnectMugIdentifiers = "swiftea.autoConnectMugIdentifiers"
    static let manuallyDisconnectedMugIdentifiers = "swiftea.manuallyDisconnectedMugIdentifiers"
    static let savedMugNames = "swiftea.savedMugNames"
    static let themePreference = "swiftea.themePreference"
    static let temperatureUnitPreference = "swiftea.temperatureUnitPreference"
    static let timeFormatPreference = "swiftea.timeFormatPreference"
    static let chartTimeframePreference = "swiftea.chartTimeframePreference"
    static let keepsRunningWhenWindowClosed = "swiftea.keepsRunningWhenWindowClosed"
    static let appLocationPreference = "swiftea.appLocationPreference"
    static let targetTemperatureNotificationsEnabled = "swiftea.targetTemperatureNotificationsEnabled"
    static let batteryFullyChargedNotificationsEnabled = "swiftea.batteryFullyChargedNotificationsEnabled"
    static let batteryFullyDischargedNotificationsEnabled = "swiftea.batteryFullyDischargedNotificationsEnabled"
    static let soundsEnabled = "swiftea.soundsEnabled"
    static let lastPresentedChangelogVersion = "swiftea.lastPresentedChangelogVersion"
    static let hasCompletedOnboarding = "swiftea.hasCompletedOnboarding"
    static let acceptedTermsVersion = "swiftea.acceptedTermsVersion"
    static let acceptedTermsDate = "swiftea.acceptedTermsDate"
    static let acceptedSafetyNoticeVersion = "swiftea.acceptedSafetyNoticeVersion"
    static let acceptedSafetyNoticeDate = "swiftea.acceptedSafetyNoticeDate"
}

@MainActor
final class UserDefaultsAppPreferencesStore: AppPreferencesStore {
    static let shared = UserDefaultsAppPreferencesStore(userDefaults: .standard)

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func bool(forKey key: String) -> Bool? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.bool(forKey: key)
    }

    func double(forKey key: String) -> Double? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.double(forKey: key)
    }

    func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    func set(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func set(_ value: Double, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}

@MainActor
final class InMemoryAppPreferencesStore: AppPreferencesStore {
    private var bools: [String: Bool] = [:]
    private var doubles: [String: Double] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) -> Bool? {
        bools[key]
    }

    func double(forKey key: String) -> Double? {
        doubles[key]
    }

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func set(_ value: Bool, forKey key: String) {
        bools[key] = value
    }

    func set(_ value: Double, forKey key: String) {
        doubles[key] = value
    }

    func set(_ value: String, forKey key: String) {
        strings[key] = value
    }

    func removeValue(forKey key: String) {
        bools.removeValue(forKey: key)
        doubles.removeValue(forKey: key)
        strings.removeValue(forKey: key)
    }
}
