import AppKit
import Foundation
import Observation
import OSLog

@MainActor
protocol EmberMugBluetoothCoordinating: AnyObject {
    func retryScan()
    func setPreferredPeripheralIdentifier(_ identifier: String?)
    func setAutoConnectPeripheralIdentifiers(_ identifiers: [String])
    func recoverAutoConnectMugs()
    func connectToCandidate(identifier: String)
    func stopDiscoveryScan()
    func scanForPreferredMug()
    func disconnectMug(identifier: String)
    func forgetMug(identifier: String)
    func startDiscoveryScan(excluding identifiers: [String])
    func refreshReadings()
    func refreshReadings(for identifier: String?)
    func setTargetTemperature(_ celsius: Double?, for identifier: String?)
}

extension EmberMugBluetoothCoordinator: EmberMugBluetoothCoordinating {}

@MainActor
@Observable
final class AppModel {
    private struct PendingHeatingTransition {
        let expectedTargetTemperatureCelsius: Double?
        let startedAt: Date

        var expiresAt: Date {
            startedAt.addingTimeInterval(2.5)
        }

        func matches(_ targetTemperatureCelsius: Double) -> Bool {
            if let expectedTargetTemperatureCelsius {
                return abs(targetTemperatureCelsius - expectedTargetTemperatureCelsius) < 0.35
            }

            return targetTemperatureCelsius <= 0.01
        }
    }

    private struct LocalHeatingIntent {
        let expectedTargetTemperatureCelsius: Double?

        func matches(_ targetTemperatureCelsius: Double) -> Bool {
            if let expectedTargetTemperatureCelsius {
                return abs(targetTemperatureCelsius - expectedTargetTemperatureCelsius) < 0.35
            }

            return targetTemperatureCelsius <= 0.01
        }
    }

    enum ConnectionState: Identifiable, Equatable {
        case starting
        case permissionNeeded
        case bluetoothUnavailable
        case scanning
        case choosing
        case connecting
        case connected
        case disconnected
        case error

        var id: String { title }

        var title: String {
            switch self {
            case .starting:
                "Checking Bluetooth"
            case .permissionNeeded:
                "Bluetooth permission needed"
            case .bluetoothUnavailable:
                "Bluetooth unavailable"
            case .scanning:
                "Looking for mug"
            case .choosing:
                "Choose mug"
            case .connecting:
                "Connecting"
            case .connected:
                "Connected"
            case .disconnected:
                "Connection lost"
            case .error:
                "Connection problem"
            }
        }

        var systemImage: String {
            switch self {
            case .starting:
                "antenna.radiowaves.left.and.right"
            case .permissionNeeded:
                "lock.shield.fill"
            case .bluetoothUnavailable:
                "bolt.horizontal"
            case .scanning:
                "magnifyingglass"
            case .choosing:
                "list.bullet.rectangle.fill"
            case .connecting:
                "dot.radiowaves.left.and.right"
            case .connected:
                "checkmark.circle.fill"
            case .disconnected:
                "wifi.slash"
            case .error:
                "exclamationmark.triangle.fill"
            }
        }
    }

    enum EmptyHeatingAlertPresentation: Equatable {
        case mainWindow
        case menuBar
    }

    private struct SavedMugNamesPayload: Codable {
        let namesByIdentifier: [String: String]
    }

    private struct SavedMugIdentifiersPayload: Codable {
        let identifiers: [String]
    }

    private struct TargetTemperatureDraftsPayload: Codable {
        let draftsByIdentifier: [String: Double]
    }

    private struct InitialHeatingSafetyState {
        var peripheralIdentifier: String?
        var isAwaitingContentsDecision = false
        var didBeginSafety = false
    }

    private struct MugSessionState {
        let identifier: String
        var connectionState: ConnectionState = .disconnected
        var activePeripheralIdentifier: String?
        var deviceName = "Ember Mug 2"
        var deviceBluetoothName: String?
        var deviceFinish: EmberMugFinish?
        var deviceSize: EmberMugSize?
        var deviceSerialNumber: String?
        var currentTemperatureCelsius: Double?
        var isTemperatureControlOff = true
        var emptyHeatingAlertPresentation: EmptyHeatingAlertPresentation?
        var targetTemperatureDraftCelsius = 57.0
        var batteryLevel: Double?
        var isCharging = false
        var contentsLevelRaw: Int?
        var liquidStateDescription: String?
        var isEmpty: Bool?
        var statusMessage = "Not connected."
        var discoveryLabel = "Disconnected"
        var lastConnectedAtLabel = "No mug connected yet"
        var lastReadingAtLabel = "No live readings yet"
        var lastTargetWriteAtLabel = "No target changes yet"
        var lastDiscoveryDetail = "This mug is saved, but not connected."
        var canReadCurrentTemperature = false
        var canReadTargetTemperature = false
        var canReadBattery = false
        var canReadContents = false
        var canReadActivity = false
        var canWriteTargetTemperature = false

        var hasLiveDashboardData: Bool {
            currentTemperatureCelsius != nil
                || batteryLevel != nil
                || isEmpty != nil
                || contentsLevelRaw != nil
                || liquidStateDescription != nil
        }
    }

    struct Preset: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let celsius: Double
    }

    enum ThemePreference: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system:
                "System"
            case .light:
                "Light"
            case .dark:
                "Dark"
            }
        }

        var symbolName: String {
            switch self {
            case .system:
                "circle.lefthalf.filled"
            case .light:
                "sun.max.fill"
            case .dark:
                "moon.fill"
            }
        }
    }

    enum TemperatureUnitPreference: String, CaseIterable, Identifiable {
        case celsius
        case fahrenheit

        var id: String { rawValue }

        var title: String {
            switch self {
            case .celsius:
                "Celsius"
            case .fahrenheit:
                "Fahrenheit"
            }
        }

        var measurementUnit: UnitTemperature {
            switch self {
            case .celsius:
                .celsius
            case .fahrenheit:
                .fahrenheit
            }
        }
    }

    enum TimeFormatPreference: String, CaseIterable, Identifiable {
        case twentyFourHour
        case twelveHour

        var id: String { rawValue }

        var title: String {
            switch self {
            case .twentyFourHour:
                "24-hour"
            case .twelveHour:
                "12-hour (am/pm)"
            }
        }

        var chartXAxisLabelWidth: CGFloat {
            40
        }

        var chartXAxisLabelFontSize: CGFloat {
            switch self {
            case .twentyFourHour:
                10
            case .twelveHour:
                9
            }
        }

        var chartXAxisMeridiemLabelFontSize: CGFloat {
            max(chartXAxisLabelFontSize - 1, 1)
        }
    }

    struct SystemPreferenceDefaults: Equatable {
        let temperatureUnitPreference: TemperatureUnitPreference
        let timeFormatPreference: TimeFormatPreference

        static let stableTesting = SystemPreferenceDefaults(
            temperatureUnitPreference: .celsius,
            timeFormatPreference: .twentyFourHour
        )

        static func current(locale: Locale = .autoupdatingCurrent) -> SystemPreferenceDefaults {
            SystemPreferenceDefaults(
                temperatureUnitPreference: defaultTemperatureUnit(for: locale),
                timeFormatPreference: defaultTimeFormat(for: locale)
            )
        }

        private static func defaultTemperatureUnit(for locale: Locale) -> TemperatureUnitPreference {
            locale.measurementSystem == .us ? .fahrenheit : .celsius
        }

        private static func defaultTimeFormat(for locale: Locale) -> TimeFormatPreference {
            let hourFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
            return hourFormat.contains("a") || hourFormat.contains("h") || hourFormat.contains("K")
                ? .twelveHour
                : .twentyFourHour
        }
    }

    enum ChartTimeframePreference: String, CaseIterable, Identifiable {
        case oneHour
        case threeHours
        case sixHours
        case twelveHours
        case twentyFourHours

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneHour:
                "1 hour"
            case .threeHours:
                "3 hours"
            case .sixHours:
                "6 hours"
            case .twelveHours:
                "12 hours"
            case .twentyFourHours:
                "24 hours"
            }
        }

        var duration: TimeInterval {
            switch self {
            case .oneHour:
                60 * 60
            case .threeHours:
                3 * 60 * 60
            case .sixHours:
                6 * 60 * 60
            case .twelveHours:
                12 * 60 * 60
            case .twentyFourHours:
                24 * 60 * 60
            }
        }

        var xAxisStrideMinutes: Int {
            switch self {
            case .oneHour:
                15
            case .threeHours:
                30
            case .sixHours:
                60
            case .twelveHours:
                120
            case .twentyFourHours:
                240
            }
        }
    }

    enum AppLocationPreference: String, CaseIterable, Identifiable {
        case dock
        case menuBar
        case dockAndMenuBar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dock:
                "Dock"
            case .menuBar:
                "Menu Bar"
            case .dockAndMenuBar:
                "Dock and Menu Bar"
            }
        }

        var includesDock: Bool {
            switch self {
            case .dock, .dockAndMenuBar:
                true
            case .menuBar:
                false
            }
        }

        var includesMenuBar: Bool {
            switch self {
            case .menuBar, .dockAndMenuBar:
                true
            case .dock:
                false
            }
        }

        var activationPolicy: NSApplication.ActivationPolicy {
            includesDock ? .regular : .accessory
        }
    }

    struct SidebarMugItem: Identifiable, Equatable {
        enum Kind: Equatable {
            case current
            case nearby
            case saved
        }

        let identifier: String
        let name: String
        let subtitle: String
        let signalLabel: String?
        let finish: EmberMugFinish?
        let size: EmberMugSize?
        let kind: Kind
        let isConnected: Bool
        let isPreferred: Bool

        var id: String { identifier }
    }

    struct DiscoveryMugItem: Identifiable, Equatable {
        let identifier: String
        let name: String
        let metadata: String

        var id: String { identifier }
    }

    private struct LoggedMugHistoryState: Equatable {
        let isConnected: Bool
        let batteryPercent: Int?
        let temperatureCelsius: Double?
        let isHeatingOn: Bool
    }

    private struct TrustedBatteryReading {
        let percent: Int
        let timestamp: Date
    }

    private struct PendingBatteryReading {
        let percent: Int
        let firstSeenAt: Date
        let latestSeenAt: Date
        let sampleCount: Int
    }

    private struct BatteryTrustResult {
        let level: Double?
        let historyKindOverride: MugHistoryEventKind?
    }

    private enum NotificationPreference: Sendable {
        case targetTemperature
        case batteryFullyCharged
        case batteryFullyDischarged

        var preferenceKey: String {
            switch self {
            case .targetTemperature:
                AppPreferencesKey.targetTemperatureNotificationsEnabled
            case .batteryFullyCharged:
                AppPreferencesKey.batteryFullyChargedNotificationsEnabled
            case .batteryFullyDischarged:
                AppPreferencesKey.batteryFullyDischargedNotificationsEnabled
            }
        }
    }

    private struct TargetTemperatureNotificationState {
        enum ApproachSide {
            case below
            case above
        }

        var armedTargetCelsius: Double?
        var armedSide: ApproachSide?
        var notifiedTargetCelsius: Double?
    }

    private struct BatteryNotificationState {
        var lastPercent: Int?
        var didNotifyFullyCharged = false
        var didNotifyFullyDischarged = false
    }

    @ObservationIgnored private var bluetoothCoordinator: (any EmberMugBluetoothCoordinating)?
    @ObservationIgnored private var deferredBluetoothCoordinator: (any EmberMugBluetoothCoordinating)?
    @ObservationIgnored private let preferences: AppPreferencesStore
    @ObservationIgnored private let mugHistoryStore: any MugHistoryStoring
    @ObservationIgnored private let targetTemperatureNotifier: any TargetTemperatureNotificationDelivering
    @ObservationIgnored private let idleSleepPreventionManager: any IdleSleepPreventionManaging
    @ObservationIgnored private let loginItemManager: any LoginItemManaging
    @ObservationIgnored private let appSessionID: UUID
    @ObservationIgnored private let appVersionIdentifier: String
    @ObservationIgnored private let changelogMarkdown: String
    @ObservationIgnored private let nowProvider: () -> Date
    @ObservationIgnored private var didBecomeActiveObserver: NSObjectProtocol?
    @ObservationIgnored private var didWakeObserver: NSObjectProtocol?
    @ObservationIgnored private var rawDiscoveredMugs: [BluetoothRuntimeSnapshot.DiscoveredMug] = []
    @ObservationIgnored private var deviceBluetoothName: String?
    @ObservationIgnored private var savedMugNamesByIdentifier: [String: String] = [:]
    @ObservationIgnored private var manuallyDisconnectedMugIdentifiers: Set<String> = []
    @ObservationIgnored private var targetTemperatureDraftsByMug: [String: Double] = [:]
    @ObservationIgnored private var userChosenTargetTemperatureDraftIdentifiers: Set<String> = []
    @ObservationIgnored private var hasUserChosenGlobalTargetTemperatureDraft = false
    @ObservationIgnored private var pendingHeatingTransitionByMug: [String: PendingHeatingTransition] = [:]
    @ObservationIgnored private var localHeatingIntentByMug: [String: LocalHeatingIntent] = [:]
    @ObservationIgnored private var pendingStandaloneHeatingRearmTargetByMug: [String: Double] = [:]
    @ObservationIgnored private var pendingTargetTemperatureCommitTaskByMug: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingTemperatureControlCommitTaskByMug: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var initialHeatingSafetyByMug: [String: InitialHeatingSafetyState] = [:]
    @ObservationIgnored private var editingTargetTemperatureMugIdentifiers: Set<String> = []
    @ObservationIgnored private var sideEffectMugIdentifierOverride: String?
    @ObservationIgnored private let heatingToggleSoundPlayer: any HeatingToggleSoundPlaying
    @ObservationIgnored private var lastLoggedHistoryStateByMug: [String: LoggedMugHistoryState] = [:]
    @ObservationIgnored private var lastTrustedBatteryReadingByMug: [String: TrustedBatteryReading] = [:]
    @ObservationIgnored private var pendingBatteryReadingByMug: [String: PendingBatteryReading] = [:]
    @ObservationIgnored private var lastProcessedBatteryReadingAtByMug: [String: Date] = [:]
    @ObservationIgnored private var targetTemperatureNotificationStateByMug: [String: TargetTemperatureNotificationState] = [:]
    @ObservationIgnored private var batteryNotificationStateByMug: [String: BatteryNotificationState] = [:]
    @ObservationIgnored private var isDiscoveryWindowOpen = false
    @ObservationIgnored private var pendingDiscoveryConnectionIdentifiers: Set<String> = []
    @ObservationIgnored private var isRestoringSavedPreferences = false
    @ObservationIgnored private let startsRuntimeWhenLegallyAuthorized: Bool
    @ObservationIgnored private var hasStartedLegallyAuthorizedRuntime = false
    @ObservationIgnored private var didPresentOnboardingThisSession = false

    private static let targetTemperatureRangeCelsius = 50.0 ... 62.0
    private static let targetTemperatureRangeFahrenheit = 122.0 ... 143.0
    private static let immediateBatteryDeltaPercent = 2
    private static let batteryRecalibrationStableTolerancePercent = 1
    private static let batteryRecalibrationMinimumSampleCount = 3
    private static let batteryRecalibrationMinimumDuration: TimeInterval = 90
    private static let chargingBatteryIncreasePercentPerMinute = 1.25
    private static let unpluggedBatteryIncreasePercentPerMinute = 0.25
    private static let chargingBatteryDropPercentPerMinute = 0.5
    private static let unpluggedBatteryDropPercentPerMinute = 2.0
    private static let batteryIncreaseTolerancePercent = 2.0
    private static let batteryDropTolerancePercent = 3.0
    private static let legacyBatterySegmentBreakThresholdPercent = 10
    private static let legacyBatterySegmentBreakWindow: TimeInterval = 10 * 60
    static let maximumMugNameCharacterCount = 18

    let targetTemperatureRange = AppModel.targetTemperatureRangeCelsius

    var connectionState: ConnectionState = .starting
    var activePeripheralIdentifier: String?
    var deviceName = "Ember Mug 2"
    var deviceFinish: EmberMugFinish?
    var deviceSize: EmberMugSize?
    var deviceSerialNumber: String?
    var currentTemperatureCelsius: Double?
    var isTemperatureControlOff = true
    var emptyHeatingAlertPresentation: EmptyHeatingAlertPresentation?
    private(set) var targetTemperatureDraftCelsius = 57.0
    var batteryLevel: Double?
    var isCharging = false
    var contentsLevelRaw: Int?
    var liquidStateDescription: String?
    var isEmpty: Bool?
    var discoveredMugs: [BluetoothRuntimeSnapshot.DiscoveredMug] = []
    var preferredPeripheralIdentifier: String?
    var selectedMugIdentifier: String? {
        didSet {
            guard oldValue != selectedMugIdentifier else { return }
            persistSelectedMugIdentifier()
        }
    }
    private(set) var savedMugIdentifiers: [String] = [] {
        didSet {
            persistSavedMugIdentifiers()
        }
    }
    private(set) var autoConnectMugIdentifiers: [String] = [] {
        didSet {
            persistAutoConnectMugIdentifiers()
        }
    }
    private var mugSessionsByIdentifier: [String: MugSessionState] = [:]
    var isPresentingMugNameSheet = false
    var mugNameDraft = "" {
        didSet {
            let limitedName = Self.limitedMugName(mugNameDraft)
            if limitedName != mugNameDraft {
                mugNameDraft = limitedName
            }
        }
    }
    private var mugNameEditingIdentifier: String?
    private(set) var sidebarMugNameEditingIdentifier: String?
    var sidebarMugNameDraft = "" {
        didSet {
            let limitedName = Self.limitedMugName(sidebarMugNameDraft)
            if limitedName != sidebarMugNameDraft {
                sidebarMugNameDraft = limitedName
            }
        }
    }
    var statusMessage = "Checking Bluetooth availability on this Mac."
    var bluetoothAccessLabel = "Checking"
    var bluetoothHardwareLabel = "Checking"
    var discoveryLabel = "Starting"
    var lastConnectedAtLabel = "No mug connected yet"
    var lastReadingAtLabel = "No live readings yet"
    var lastTargetWriteAtLabel = "No target changes yet"
    var lastDiscoveryDetail = "Swiftea is preparing Bluetooth."
    var themePreference: ThemePreference = .system {
        didSet {
            preferences.set(themePreference.rawValue, forKey: AppPreferencesKey.themePreference)
        }
    }
    var temperatureUnitPreference: TemperatureUnitPreference = .celsius {
        didSet {
            normalizeTargetTemperatureDraftForCurrentUnit()
            guard !isRestoringSavedPreferences else { return }
            preferences.set(temperatureUnitPreference.rawValue, forKey: AppPreferencesKey.temperatureUnitPreference)
        }
    }
    var timeFormatPreference: TimeFormatPreference = .twentyFourHour {
        didSet {
            guard !isRestoringSavedPreferences else { return }
            preferences.set(timeFormatPreference.rawValue, forKey: AppPreferencesKey.timeFormatPreference)
        }
    }
    var chartTimeframePreference: ChartTimeframePreference = .threeHours {
        didSet {
            preferences.set(chartTimeframePreference.rawValue, forKey: AppPreferencesKey.chartTimeframePreference)
        }
    }
    var keepsRunningWhenWindowClosed = true {
        didSet {
            preferences.set(keepsRunningWhenWindowClosed, forKey: AppPreferencesKey.keepsRunningWhenWindowClosed)
        }
    }
    var appLocationPreference: AppLocationPreference = .dockAndMenuBar {
        didSet {
            preferences.set(appLocationPreference.rawValue, forKey: AppPreferencesKey.appLocationPreference)
        }
    }
    private(set) var launchesAtLogin = false
    var isPresentingLoginItemAlert = false
    var loginItemAlertTitle = ""
    var loginItemAlertMessage = ""
    var loginItemAlertOffersSystemSettings = false
    var chartNowOverride: Date?
    private(set) var targetTemperatureNotificationsEnabled = false {
        didSet {
            guard oldValue != targetTemperatureNotificationsEnabled else { return }
            preferences.set(targetTemperatureNotificationsEnabled, forKey: AppPreferencesKey.targetTemperatureNotificationsEnabled)

            if !targetTemperatureNotificationsEnabled {
                targetTemperatureNotificationStateByMug.removeAll()
            }
        }
    }
    private(set) var batteryFullyChargedNotificationsEnabled = false {
        didSet {
            guard oldValue != batteryFullyChargedNotificationsEnabled else { return }
            preferences.set(batteryFullyChargedNotificationsEnabled, forKey: AppPreferencesKey.batteryFullyChargedNotificationsEnabled)
        }
    }
    private(set) var batteryFullyDischargedNotificationsEnabled = false {
        didSet {
            guard oldValue != batteryFullyDischargedNotificationsEnabled else { return }
            preferences.set(batteryFullyDischargedNotificationsEnabled, forKey: AppPreferencesKey.batteryFullyDischargedNotificationsEnabled)
        }
    }
    private(set) var soundsEnabled = true {
        didSet {
            guard oldValue != soundsEnabled else { return }
            preferences.set(soundsEnabled, forKey: AppPreferencesKey.soundsEnabled)
        }
    }
    var isRequestingNotificationPermission = false
    var isPresentingNotificationPermissionAlert = false
    var notificationPermissionAlertMessage = ""
    private(set) var shouldPresentOnboarding = false
    private(set) var shouldStartOnboardingAtLegalAgreement = false
    private(set) var shouldPresentUpdateChangelog = false
    private(set) var updateChangelogReleases: [PublishedChangelog.Release] = []
    private(set) var mugHistoryEvents: [MugHistoryEvent] = []
    var canReadCurrentTemperature = false
    var canReadTargetTemperature = false
    var canReadBattery = false
    var canReadContents = false
    var canReadActivity = false
    var canWriteTargetTemperature = false
    var presets = [
        Preset(title: "Coffee", celsius: 57.0),
        Preset(title: "Tea", celsius: 60.0),
        Preset(title: "Warm", celsius: 52.0)
    ]

    private var transientMugIdentifier: String? {
        sideEffectMugIdentifierOverride
            ?? activePeripheralIdentifier
            ?? selectedMugIdentifier
            ?? preferredPeripheralIdentifier
    }

    private var pendingHeatingTransition: PendingHeatingTransition? {
        get {
            guard let transientMugIdentifier else { return nil }
            return pendingHeatingTransitionByMug[transientMugIdentifier]
        }
        set {
            guard let transientMugIdentifier else { return }
            pendingHeatingTransitionByMug[transientMugIdentifier] = newValue
        }
    }

    private var localHeatingIntent: LocalHeatingIntent? {
        get {
            guard let transientMugIdentifier else { return nil }
            return localHeatingIntentByMug[transientMugIdentifier]
        }
        set {
            guard let transientMugIdentifier else { return }
            localHeatingIntentByMug[transientMugIdentifier] = newValue
        }
    }

    private var pendingStandaloneHeatingRearmTarget: Double? {
        get {
            guard let transientMugIdentifier else { return nil }
            return pendingStandaloneHeatingRearmTargetByMug[transientMugIdentifier]
        }
        set {
            guard let transientMugIdentifier else { return }
            pendingStandaloneHeatingRearmTargetByMug[transientMugIdentifier] = newValue
        }
    }

    private var pendingTargetTemperatureCommitTask: Task<Void, Never>? {
        get {
            guard let transientMugIdentifier else { return nil }
            return pendingTargetTemperatureCommitTaskByMug[transientMugIdentifier]
        }
        set {
            guard let transientMugIdentifier else { return }
            pendingTargetTemperatureCommitTaskByMug[transientMugIdentifier] = newValue
        }
    }

    private var pendingTemperatureControlCommitTask: Task<Void, Never>? {
        get {
            guard let transientMugIdentifier else { return nil }
            return pendingTemperatureControlCommitTaskByMug[transientMugIdentifier]
        }
        set {
            guard let transientMugIdentifier else { return }
            pendingTemperatureControlCommitTaskByMug[transientMugIdentifier] = newValue
        }
    }

    private var initialHeatingSafetyPeripheralIdentifier: String? {
        get {
            guard let transientMugIdentifier else { return nil }
            return initialHeatingSafetyByMug[transientMugIdentifier]?.peripheralIdentifier
        }
        set {
            guard let transientMugIdentifier else { return }
            var state = initialHeatingSafetyByMug[transientMugIdentifier] ?? InitialHeatingSafetyState()
            state.peripheralIdentifier = newValue
            initialHeatingSafetyByMug[transientMugIdentifier] = state
        }
    }

    private var isAwaitingInitialContentsDecision: Bool {
        get {
            guard let transientMugIdentifier else { return false }
            return initialHeatingSafetyByMug[transientMugIdentifier]?.isAwaitingContentsDecision ?? false
        }
        set {
            guard let transientMugIdentifier else { return }
            var state = initialHeatingSafetyByMug[transientMugIdentifier] ?? InitialHeatingSafetyState()
            state.isAwaitingContentsDecision = newValue
            initialHeatingSafetyByMug[transientMugIdentifier] = state
        }
    }

    private var didBeginInitialHeatingSafety: Bool {
        get {
            guard let transientMugIdentifier else { return false }
            return initialHeatingSafetyByMug[transientMugIdentifier]?.didBeginSafety ?? false
        }
        set {
            guard let transientMugIdentifier else { return }
            var state = initialHeatingSafetyByMug[transientMugIdentifier] ?? InitialHeatingSafetyState()
            state.didBeginSafety = newValue
            initialHeatingSafetyByMug[transientMugIdentifier] = state
        }
    }

    private var isEditingTargetTemperature: Bool {
        get {
            guard let transientMugIdentifier else { return false }
            return editingTargetTemperatureMugIdentifiers.contains(transientMugIdentifier)
        }
        set {
            guard let transientMugIdentifier else { return }
            if newValue {
                editingTargetTemperatureMugIdentifiers.insert(transientMugIdentifier)
            } else {
                editingTargetTemperatureMugIdentifiers.remove(transientMugIdentifier)
            }
        }
    }

    init(
        startBluetooth: Bool = true,
        preferences: AppPreferencesStore = UserDefaultsAppPreferencesStore.shared,
        heatingToggleSoundPlayer: (any HeatingToggleSoundPlaying)? = nil,
        targetTemperatureNotifier: (any TargetTemperatureNotificationDelivering)? = nil,
        idleSleepPreventionManager: (any IdleSleepPreventionManaging)? = nil,
        loginItemManager: (any LoginItemManaging)? = nil,
        mugHistoryStore: (any MugHistoryStoring)? = nil,
        bluetoothCoordinator: (any EmberMugBluetoothCoordinating)? = nil,
        appSessionID: UUID = UUID(),
        appVersionIdentifier: String = AppVersion.currentIdentifier(),
        changelogMarkdown: String = PublishedChangelog.bundledMarkdown(),
        systemPreferenceDefaults: SystemPreferenceDefaults? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.mugHistoryStore = mugHistoryStore ?? (startBluetooth ? MugHistoryFileStore.shared : InMemoryMugHistoryStore())
        self.appSessionID = appSessionID
        self.appVersionIdentifier = appVersionIdentifier
        self.changelogMarkdown = changelogMarkdown
        self.startsRuntimeWhenLegallyAuthorized = startBluetooth
        self.nowProvider = nowProvider
        self.heatingToggleSoundPlayer = heatingToggleSoundPlayer
            ?? (startBluetooth ? NativeHeatingToggleSoundPlayer.shared : SilentHeatingToggleSoundPlayer.shared)
        self.targetTemperatureNotifier = targetTemperatureNotifier
            ?? (startBluetooth ? NativeTargetTemperatureNotificationCenter.shared : SilentTargetTemperatureNotificationCenter.shared)
        self.idleSleepPreventionManager = idleSleepPreventionManager
            ?? (startBluetooth ? NativeIdleSleepPreventionManager.shared : NoOpIdleSleepPreventionManager.shared)
        self.loginItemManager = loginItemManager
            ?? (startBluetooth ? NativeLoginItemManager.shared : NoOpLoginItemManager.shared)
        if startBluetooth {
            self.bluetoothCoordinator = nil
            self.deferredBluetoothCoordinator = bluetoothCoordinator
        } else {
            self.bluetoothCoordinator = bluetoothCoordinator
            self.deferredBluetoothCoordinator = nil
        }
        let resolvedSystemPreferenceDefaults = systemPreferenceDefaults
            ?? (startBluetooth ? .current() : .stableTesting)
        isRestoringSavedPreferences = true
        self.temperatureUnitPreference = resolvedSystemPreferenceDefaults.temperatureUnitPreference
        self.timeFormatPreference = resolvedSystemPreferenceDefaults.timeFormatPreference
        isRestoringSavedPreferences = false
        restoreSavedPreferences()
        refreshLaunchAtLoginStatus()
        restoreOnboardingPresentationState()
        restoreUpdateChangelogPresentationState()
        if startBluetooth {
            startLegallyAuthorizedRuntimeIfNeeded()
        } else {
            installLifecycleObservers()
            loadMugHistoryAndRecordSessionStart()
        }
    }

    static func launchModel() -> AppModel {
        AppModel()
    }

    var canAdjustTemperature: Bool {
        connectionState == .connected && canWriteTargetTemperature
    }

    func consumeUpdateChangelogPresentation() -> Bool {
        guard shouldPresentUpdateChangelog else { return false }

        shouldPresentUpdateChangelog = false
        preferences.set(appVersionIdentifier, forKey: AppPreferencesKey.lastPresentedChangelogVersion)
        return true
    }

    func consumeOnboardingPresentation() -> Bool {
        guard shouldPresentOnboarding, !didPresentOnboardingThisSession else { return false }

        didPresentOnboardingThisSession = true
        return true
    }

    var hasAcceptedCurrentTermsOfUse: Bool {
        preferences.string(forKey: AppPreferencesKey.acceptedTermsVersion)
            == SwifteaLegalDocuments.currentTermsVersion
    }

    var hasAcceptedCurrentSafetyNotice: Bool {
        preferences.string(forKey: AppPreferencesKey.acceptedSafetyNoticeVersion)
            == SwifteaLegalDocuments.currentSafetyNoticeVersion
    }

    var hasAcceptedCurrentLegalDocuments: Bool {
        hasAcceptedCurrentTermsOfUse && hasAcceptedCurrentSafetyNotice
    }

    func acceptCurrentLegalDocumentsAndCompleteOnboarding() {
        let acceptanceDate = ISO8601DateFormatter().string(from: nowProvider())

        preferences.set(
            SwifteaLegalDocuments.currentTermsVersion,
            forKey: AppPreferencesKey.acceptedTermsVersion
        )
        preferences.set(acceptanceDate, forKey: AppPreferencesKey.acceptedTermsDate)
        preferences.set(
            SwifteaLegalDocuments.currentSafetyNoticeVersion,
            forKey: AppPreferencesKey.acceptedSafetyNoticeVersion
        )
        preferences.set(acceptanceDate, forKey: AppPreferencesKey.acceptedSafetyNoticeDate)
        shouldPresentOnboarding = false
        shouldStartOnboardingAtLegalAgreement = false
        preferences.set(true, forKey: AppPreferencesKey.hasCompletedOnboarding)
        startLegallyAuthorizedRuntimeIfNeeded()
    }

    var activeHistoryMugIdentifier: String? {
        sideEffectMugIdentifierOverride
            ?? selectedMugIdentifier
            ?? activePeripheralIdentifier
            ?? preferredPeripheralIdentifier
    }

    func historyChartSegments(metric: MugHistoryMetric, now: Date = Date()) -> [MugHistoryChartSegment] {
        guard let mugIdentifier = activeHistoryMugIdentifier else { return [] }

        let windowStart = now.addingTimeInterval(-chartTimeframePreference.duration)
        let displayUnit = temperatureUnitPreference
        let events = mugHistoryEvents
            .filter { $0.mugIdentifier == mugIdentifier && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        guard !events.isEmpty else { return [] }

        struct DerivedPoint {
            let segmentID: String
            let timestamp: Date
            let value: Double
        }

        var connected = false
        var heatingOn = false
        var batteryPercent: Int?
        var lastBatterySample: (percent: Int, timestamp: Date)?
        var temperatureCelsius: Double?
        var currentSessionID: UUID?
        var segmentIndex = 0
        var currentSegmentID: String?
        var derivedPoints: [DerivedPoint] = []

        func makeSegmentID(sessionID: UUID, index: Int) -> String {
            "\(sessionID.uuidString)-\(index)"
        }

        func currentValue() -> Double? {
            switch metric {
            case .battery:
                guard connected, let batteryPercent else { return nil }
                return Double(batteryPercent)
            case .temperature:
                guard connected, heatingOn, let temperatureCelsius else { return nil }
                return Self.temperatureDisplayValue(celsius: temperatureCelsius, unit: displayUnit)
            }
        }

        for event in events {
            if currentSessionID != event.appSessionID {
                currentSessionID = event.appSessionID
                connected = false
                heatingOn = false
                batteryPercent = nil
                lastBatterySample = nil
                temperatureCelsius = nil
                currentSegmentID = nil
                segmentIndex = 0
            }

            let wasConnected = connected
            let wasHeatingOn = heatingOn
            let previousBatterySample = lastBatterySample

            connected = event.isConnected
            if let isHeatingOn = event.isHeatingOn {
                heatingOn = isHeatingOn
            }
            batteryPercent = event.batteryPercent
            if let batteryPercent {
                lastBatterySample = (batteryPercent, event.timestamp)
            }
            temperatureCelsius = event.temperatureCelsius

            guard let sessionID = currentSessionID else { continue }

            let shouldBreakSegment: Bool
            switch metric {
            case .battery:
                shouldBreakSegment = connected && (
                    !wasConnected
                        || event.kind == .batteryRecalibrated
                        || Self.shouldBreakLegacyBatterySegment(
                            previous: previousBatterySample,
                            nextPercent: batteryPercent,
                            nextTimestamp: event.timestamp
                        )
                )
            case .temperature:
                shouldBreakSegment = connected && (!wasConnected || (heatingOn && !wasHeatingOn))
            }

            if shouldBreakSegment || currentSegmentID == nil {
                segmentIndex += 1
                currentSegmentID = makeSegmentID(sessionID: sessionID, index: segmentIndex)
            }

            guard let currentSegmentID, let value = currentValue() else { continue }
            derivedPoints.append(
                DerivedPoint(
                    segmentID: currentSegmentID,
                    timestamp: event.timestamp,
                    value: value
                )
            )
        }

        if
            let currentSegmentID,
            let value = currentValue(),
            currentSessionID == appSessionID
        {
            derivedPoints.append(
                DerivedPoint(
                    segmentID: currentSegmentID,
                    timestamp: now,
                    value: value
                )
            )
        }

        let groupedPoints = Dictionary(grouping: derivedPoints, by: \.segmentID)

        return groupedPoints
            .map { segmentID, points in
                let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
                var windowPoints = sortedPoints
                    .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
                    .map {
                        MugHistoryChartPoint(
                            id: "\($0.segmentID)-\($0.timestamp.timeIntervalSince1970)",
                            timestamp: $0.timestamp,
                            value: $0.value
                        )
                    }

                if
                    let carryInPoint = sortedPoints.last(where: { $0.timestamp < windowStart }),
                    sortedPoints.contains(where: { $0.timestamp >= windowStart && $0.timestamp <= now })
                        || segmentID == currentSegmentID
                {
                    windowPoints.insert(
                        MugHistoryChartPoint(
                            id: "\(carryInPoint.segmentID)-window-start",
                            timestamp: windowStart,
                            value: carryInPoint.value
                        ),
                        at: 0
                    )
                }

                return MugHistoryChartSegment(id: segmentID, points: windowPoints)
            }
            .filter { !$0.points.isEmpty }
            .sorted { left, right in
                let leftDate = left.points.first?.timestamp ?? .distantPast
                let rightDate = right.points.first?.timestamp ?? .distantPast
                return leftDate < rightDate
            }
    }

    func historyChartTimeLabel(for date: Date) -> String {
        Self.formatTime(date, preference: timeFormatPreference)
    }

    func historyChartYDomain(for metric: MugHistoryMetric) -> ClosedRange<Double> {
        switch metric {
        case .battery:
            0 ... 100
        case .temperature:
            switch temperatureUnitPreference {
            case .celsius:
                30 ... 70
            case .fahrenheit:
                Self.temperatureDisplayValue(celsius: 30, unit: .fahrenheit)
                    ... Self.temperatureDisplayValue(celsius: 70, unit: .fahrenheit)
            }
        }
    }

    func historyChartYAxisValues(for metric: MugHistoryMetric) -> [Double] {
        switch metric {
        case .battery:
            stride(from: 0, through: 100, by: 20).map { Double($0) }
        case .temperature:
            stride(from: 30, through: 70, by: 10).map {
                Self.temperatureDisplayValue(celsius: Double($0), unit: temperatureUnitPreference)
            }
        }
    }

    var currentTemperatureLabel: String {
        if isEmpty == true {
            return "Empty"
        }

        guard let currentTemperatureCelsius else { return "—" }
        return Self.format(celsius: currentTemperatureCelsius, unit: temperatureUnitPreference)
    }

    var menuBarStatusTemperatureLabel: String? {
        guard shouldShowMugDashboard, isEmpty != true, let currentTemperatureCelsius else {
            return nil
        }

        return Self.format(celsius: currentTemperatureCelsius, unit: temperatureUnitPreference)
    }

    var menuBarCurrentTemperatureLine: String {
        if isEmpty == true {
            return "Empty"
        }

        guard let menuBarStatusTemperatureLabel else {
            return "Current temperature: —"
        }

        return "Current temperature: \(menuBarStatusTemperatureLabel)"
    }

    var menuBarTargetTemperatureLine: String {
        guard !isTemperatureControlOff else {
            return "Heating off"
        }

        return "Target temperature: \(targetTemperatureLabel)"
    }

    var menuBarBatteryLine: String {
        guard batteryLevel != nil else {
            return "Battery unavailable"
        }

        return isCharging ? "Charging: \(batteryLabel)" : "\(batteryLabel) Battery"
    }

    var targetTemperatureLabel: String {
        guard !isTemperatureControlOff else { return "Off" }
        return Self.formatTargetTemperatureValue(targetTemperatureDisplayValue, unit: temperatureUnitPreference)
    }

    var batteryLabel: String {
        guard let batteryLevel else { return "—" }
        return batteryLevel.formatted(.percent.precision(.fractionLength(0)))
    }

    var batteryFillFraction: Double {
        guard let batteryLevel else { return 0 }
        return min(max(batteryLevel, 0), 1)
    }

    var currentMugSpecificationLabel: String? {
        Self.metadataLabel(finish: deviceFinish, size: deviceSize)
    }

    var sidebarMugs: [SidebarMugItem] {
        let orderedIdentifiers = orderedKnownMugIdentifiers()

        return orderedIdentifiers.map { identifier in
            let session = mugSessionsByIdentifier[identifier]
            return SidebarMugItem(
                identifier: identifier,
                name: session.map { displayName(for: $0.deviceBluetoothName ?? $0.deviceName, identifier: identifier) }
                    ?? savedName(for: identifier),
                subtitle: session.map { sidebarSubtitle(for: $0) } ?? "Disconnected",
                signalLabel: nil,
                finish: session?.deviceFinish,
                size: session?.deviceSize,
                kind: isDashboardConnected(session) ? .current : .saved,
                isConnected: isDashboardConnected(session),
                isPreferred: selectedMugIdentifier == identifier
            )
        }
    }

    var connectedSidebarMugs: [SidebarMugItem] {
        sidebarMugs.filter(\.isConnected)
    }

    var shouldShowMugDashboard: Bool {
        guard let selectedMugIdentifier else { return false }
        return isDashboardConnected(mugSessionsByIdentifier[selectedMugIdentifier])
    }

    var currentSidebarMug: SidebarMugItem? {
        guard let identifier = selectedMugIdentifier ?? activePeripheralIdentifier ?? preferredPeripheralIdentifier else {
            return nil
        }

        if let item = sidebarMugs.first(where: { $0.identifier == identifier }) {
            return item
        }

        return SidebarMugItem(
            identifier: identifier,
            name: displayName(for: deviceBluetoothName ?? deviceName, identifier: identifier),
            subtitle: currentSidebarSubtitle,
            signalLabel: nil,
            finish: deviceFinish,
            size: deviceSize,
            kind: .current,
            isConnected: isDashboardConnected(mugSessionsByIdentifier[identifier]),
            isPreferred: selectedMugIdentifier == identifier
        )
    }

    var savedSidebarMugs: [SidebarMugItem] {
        sidebarMugs.filter { item in
            !item.isConnected && isSavedMugIdentifier(item.identifier)
        }
    }

    var allSidebarMugIdentifiers: Set<String> {
        Set(sidebarMugs.map(\.identifier))
    }

    var defaultSidebarSelectionIdentifier: String? {
        selectedMugIdentifier
            ?? activePeripheralIdentifier
            ?? connectedSidebarMugs.first?.identifier
            ?? autoConnectMugIdentifiers.first
            ?? savedSidebarMugs.first?.identifier
    }

    func isAutoConnectEnabled(for identifier: String) -> Bool {
        autoConnectMugIdentifiers.contains(identifier)
    }

    func canEnableAutoConnect(for identifier: String) -> Bool {
        isAutoConnectEnabled(for: identifier)
            || autoConnectMugIdentifiers.count < EmberMugBluetoothCoordinator.maximumSimultaneousMugs
    }

    var connectionActionTitle: String? {
        switch connectionState {
        case .permissionNeeded:
            "Open Bluetooth Settings"
        case .starting:
            "Retry"
        case .bluetoothUnavailable, .choosing, .disconnected, .error:
            "Retry Scan"
        case .connected:
            "Reconnect"
        case .scanning, .connecting:
            nil
        }
    }

    var canRefreshReadings: Bool {
        connectionState == .connected
    }

    var refreshReadingsHint: String {
        canRefreshReadings
        ? "Use this if you want to force a fresh read from the mug."
        : "Refresh becomes available after Swiftea connects to your mug."
    }

    var shouldShowDiscoveredMugs: Bool {
        false
    }

    var discoveredMugsSummary: String {
        switch discoveredMugs.count {
        case 0:
            return "No Ember mugs found yet."
        case 1:
            return "One Ember mug is nearby. You can let Swiftea try it or connect explicitly."
        default:
            return "More than one Ember mug is nearby. Pick the one you want so Swiftea stops guessing."
        }
    }

    var discoveryWindowMugs: [DiscoveryMugItem] {
        discoveredMugs
            .filter { !isDiscoveryExcludedMug($0) }
            .map { mug in
                DiscoveryMugItem(
                    identifier: mug.identifier,
                    name: mug.name,
                    metadata: Self.metadataLabel(finish: mug.finish, size: mug.size) ?? "Finish and size unknown"
                )
            }
    }

    var discoveryWindowStatusLabel: String {
        if connectedOrConnectingMugCount >= EmberMugBluetoothCoordinator.maximumSimultaneousMugs {
            return "Swiftea already has 3 mugs connected."
        }

        switch discoveryWindowMugs.count {
        case 0:
            return "Searching for nearby mugs…"
        case 1:
            return "One nearby mug found"
        default:
            return "\(discoveryWindowMugs.count) nearby mugs found"
        }
    }

    var hasSavedMugPreference: Bool {
        !savedMugIdentifiers.isEmpty
            || !autoConnectMugIdentifiers.isEmpty
            || !savedMugNamesByIdentifier.isEmpty
            || preferredPeripheralIdentifier != nil
    }

    var canEditCurrentMugName: Bool {
        guard let activePeripheralIdentifier else { return false }
        return isDashboardConnected(mugSessionsByIdentifier[activePeripheralIdentifier])
    }

    var currentMugCustomName: String? {
        guard let identifier = mugNameEditingIdentifier ?? activePeripheralIdentifier else { return nil }
        return savedMugNamesByIdentifier[identifier]
    }

    var currentMugNameActionTitle: String {
        currentMugCustomName == nil ? "Save Name" : "Rename"
    }

    var mugNameSheetTitle: String {
        currentMugCustomName == nil ? "Save Mug Name" : "Rename Mug"
    }

    var sidebarScanButtonTitle: String {
        switch connectionState {
        case .scanning:
            return "Scanning"
        case .connecting:
            return "Connecting"
        default:
            return "Connect Mug"
        }
    }

    var canTriggerSidebarScan: Bool {
        connectionState != .connecting && connectedOrConnectingMugCount < EmberMugBluetoothCoordinator.maximumSimultaneousMugs
    }

    var canOpenDiscoveryWindow: Bool {
        connectedOrConnectingMugCount < EmberMugBluetoothCoordinator.maximumSimultaneousMugs
    }

    var canRemoveCurrentMugName: Bool {
        currentMugCustomName != nil
    }

    var shouldShowHardwareDeviceName: Bool {
        guard let hardwareName = editingMugHardwareName else { return false }
        return hardwareName != (currentMugCustomName ?? mugNameDraft)
    }

    var hardwareDeviceNameLabel: String {
        editingMugHardwareName ?? "Unknown"
    }

    var bluetoothIdentifierLabel: String {
        activePeripheralIdentifier ?? "Unavailable"
    }

    var serialNumberLabel: String {
        deviceSerialNumber ?? "Unavailable"
    }

    var canCommitMugNameDraft: Bool {
        !mugNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentTemperatureCaption: String {
        switch connectionState {
        case .connected:
            if currentTemperatureCelsius != nil {
                return "Live temperature reading from your mug."
            }

            if canReadCurrentTemperature {
                return "Connected. Waiting for the mug to send its first current-temperature reading."
            }

            return "Connected, but the current-temperature path is still being confirmed for this session."
        default:
            return "Live readings will appear here once Swiftea has a stable mug session."
        }
    }

    var targetTemperatureCaption: String {
        switch connectionState {
        case .connected:
            if canWriteTargetTemperature, canReadTargetTemperature {
                return "Writes go to the mug directly, and read-back confirmation is available in this session."
            }

            if canWriteTargetTemperature {
                return "Writes are ready. Read-back confirmation is still pending on this session."
            }

            if canReadTargetTemperature {
                return "The mug’s current target can be read, but writes are not ready yet."
            }

            return "Connected, but the target-temperature path is still being confirmed."
        default:
            return "Target temperature control turns on after Swiftea confirms the mug’s read and write path."
        }
    }

    var batteryDetailLine: String {
        if batteryLevel != nil {
            return "\(batteryLabel) • \(isCharging ? "Charging" : "On battery")"
        }

        if connectionState == .connected {
            return canReadBattery
            ? "Connected • waiting for the first battery reading"
            : "Connected • battery path still being confirmed"
        }

        return "Battery details appear after the mug connects."
    }

    var contentsStatusLabel: String {
        if let isEmpty {
            return isEmpty ? "Empty" : "Has liquid"
        }

        if connectionState == .connected {
            return "Checking"
        }

        return "Unavailable"
    }

    var contentsDetailLine: String {
        if let liquidStateDescription {
            if let contentsLevelRaw {
                return "\(liquidStateDescription) • raw level \(contentsLevelRaw)"
            }

            return liquidStateDescription
        }

        if let contentsLevelRaw {
            return "Raw level \(contentsLevelRaw)"
        }

        if connectionState == .connected {
            if canReadContents || canReadActivity {
                return "Connected • waiting for contents updates"
            }

            return "Connected • contents path still being confirmed"
        }

        return "Contents details appear after the mug connects."
    }

    var contentsSymbolName: String {
        if let isEmpty {
            return isEmpty ? "mug" : "drop.fill"
        }

        return connectionState == .connected ? "drop.fill" : "questionmark.circle.fill"
    }

    var currentTemperaturePathLabel: String {
        if canReadCurrentTemperature {
            return currentTemperatureCelsius == nil ? "Ready, waiting for data" : "Ready and updating"
        }

        return connectionState == .connected ? "Connected, not confirmed yet" : "Unavailable"
    }

    var targetTemperaturePathLabel: String {
        if canWriteTargetTemperature, canReadTargetTemperature {
            return "Read and write ready"
        }

        if canWriteTargetTemperature {
            return "Write ready"
        }

        if canReadTargetTemperature {
            return "Read ready"
        }

        return connectionState == .connected ? "Connected, not confirmed yet" : "Unavailable"
    }

    var batteryPathLabel: String {
        if canReadBattery {
            return batteryLevel == nil ? "Ready, waiting for data" : "Ready and updating"
        }

        return connectionState == .connected ? "Connected, not confirmed yet" : "Unavailable"
    }

    var contentsPathLabel: String {
        if canReadContents || canReadActivity {
            if contentsLevelRaw != nil || liquidStateDescription != nil || isEmpty != nil {
                return "Ready and updating"
            }

            return "Ready, waiting for data"
        }

        return connectionState == .connected ? "Connected, not confirmed yet" : "Unavailable"
    }

    var temperatureControlHint: String {
        switch connectionState {
        case .connected:
            if isTemperatureControlOff {
                return "Heating is off. Turn it back on or choose a preset to start heating again."
            }

            return canWriteTargetTemperature
            ? "Connected and ready to write a target temperature to the mug."
            : "Connected, but target temperature control is still waiting on the writable mug characteristic."
        case .scanning, .choosing, .connecting:
            return "Controls stay off until Swiftea has a stable mug session."
        default:
            return "Controls will turn on after connection and write support are in place."
        }
    }

    var canDecreaseTargetTemperatureDraft: Bool {
        targetTemperatureDisplayValue > targetTemperatureDisplayRange.lowerBound + 0.001
    }

    var canIncreaseTargetTemperatureDraft: Bool {
        targetTemperatureDisplayValue < targetTemperatureDisplayRange.upperBound - 0.001
    }

    func performConnectionAction() {
        switch connectionState {
        case .permissionNeeded:
            SystemSettingsNavigator.openBluetoothPrivacy()
        case .starting, .bluetoothUnavailable, .choosing, .disconnected, .error, .connected:
            bluetoothCoordinator?.retryScan()
        case .scanning, .connecting:
            break
        }
    }

    func chooseDiscoveredMug(_ mug: BluetoothRuntimeSnapshot.DiscoveredMug) {
        selectMugIdentifier(mug.identifier, shouldPersistLegacyPreferred: true)
        addSavedMugIdentifier(mug.identifier)
        addAutoConnectMugIdentifier(mug.identifier)
        clearManualDisconnectSuppression(for: mug.identifier)
        preferences.set(mug.name, forKey: AppPreferencesKey.lastKnownDeviceName)
        deviceName = mug.name
        deviceFinish = mug.finish
        deviceSize = mug.size
        bluetoothCoordinator?.setPreferredPeripheralIdentifier(mug.identifier)
        synchronizeAutoConnectIdentifiersWithBluetooth()
        bluetoothCoordinator?.connectToCandidate(identifier: mug.identifier)
    }

    func connectDiscoveryMug(identifier: String) {
        guard let mug = discoveredMugs.first(where: { $0.identifier == identifier }) else { return }
        guard !isDiscoveryExcludedMug(mug) else { return }

        let shouldSelectMug = connectedSidebarMugs.isEmpty
        pendingDiscoveryConnectionIdentifiers.insert(mug.identifier)
        rawDiscoveredMugs.removeAll { $0.identifier == mug.identifier }
        discoveredMugs.removeAll { $0.identifier == mug.identifier }
        addSavedMugIdentifier(mug.identifier)
        addAutoConnectMugIdentifier(mug.identifier)
        clearManualDisconnectSuppression(for: mug.identifier)
        synchronizeAutoConnectIdentifiersWithBluetooth()

        if shouldSelectMug {
            selectMugIdentifier(mug.identifier, shouldPersistLegacyPreferred: true)
            restoreSelectedMugState()
        }

        bluetoothCoordinator?.connectToCandidate(identifier: mug.identifier)
    }

    func beginDiscoveryWindow() {
        isDiscoveryWindowOpen = true
        startDiscoveryScanIfNeeded()
    }

    func endDiscoveryWindow() {
        isDiscoveryWindowOpen = false
        bluetoothCoordinator?.stopDiscoveryScan()
        rawDiscoveredMugs = []
        discoveredMugs = []
    }

    func forgetSavedMug() {
        guard let identifier = selectedMugIdentifier ?? preferredPeripheralIdentifier else { return }
        forgetSidebarMug(identifier: identifier)
    }

    func canConnectSidebarMug(identifier: String) -> Bool {
        guard allSidebarMugIdentifiers.contains(identifier) else { return false }
        switch mugSessionsByIdentifier[identifier]?.connectionState {
        case .connected, .connecting, .scanning, .choosing, .starting:
            return false
        case .permissionNeeded, .bluetoothUnavailable, .disconnected, .error, nil:
            return connectedOrConnectingMugCount < EmberMugBluetoothCoordinator.maximumSimultaneousMugs
        }
    }

    func connectSidebarMug(identifier: String) {
        guard canConnectSidebarMug(identifier: identifier) else { return }
        addSavedMugIdentifier(identifier)
        clearManualDisconnectSuppression(for: identifier)
        selectMugIdentifier(identifier, shouldPersistLegacyPreferred: true)
        restoreSelectedMugState()
        bluetoothCoordinator?.setPreferredPeripheralIdentifier(identifier)
        synchronizeAutoConnectIdentifiersWithBluetooth()
        bluetoothCoordinator?.scanForPreferredMug()
    }

    func setAutoConnectEnabled(_ isEnabled: Bool, for identifier: String) {
        guard isSavedMugIdentifier(identifier) || allSidebarMugIdentifiers.contains(identifier) else { return }

        if isEnabled {
            guard canEnableAutoConnect(for: identifier) else { return }
            addSavedMugIdentifier(identifier)
            addAutoConnectMugIdentifier(identifier)
            clearManualDisconnectSuppression(for: identifier)
        } else {
            removeAutoConnectMugIdentifier(identifier)
        }

        synchronizeAutoConnectIdentifiersWithBluetooth()
    }

    func disconnectSidebarMug(identifier: String) {
        guard mugSessionsByIdentifier[identifier]?.connectionState == .connected else { return }
        markManualDisconnectSuppression(for: identifier)
        synchronizeAutoConnectIdentifiersWithBluetooth()
        bluetoothCoordinator?.disconnectMug(identifier: identifier)
        markMugDisconnectedLocally(identifier: identifier, detailMessage: "Disconnected.")
        selectConnectedDashboardMugIfNeeded()
        restoreSelectedMugState()
    }

    func forgetSidebarMug(identifier: String) {
        guard allSidebarMugIdentifiers.contains(identifier) else { return }

        bluetoothCoordinator?.forgetMug(identifier: identifier)
        removeAutoConnectMugIdentifier(identifier)
        clearManualDisconnectSuppression(for: identifier)
        removeSavedMugIdentifier(identifier)
        savedMugNamesByIdentifier.removeValue(forKey: identifier)
        persistSavedMugNames()
        targetTemperatureDraftsByMug.removeValue(forKey: identifier)
        persistTargetTemperatureDraftsByMug()
        removeRuntimeState(for: identifier)
        mugSessionsByIdentifier.removeValue(forKey: identifier)

        if activePeripheralIdentifier == identifier {
            clearActiveMugStateAfterForget()
        }

        if preferredPeripheralIdentifier == identifier {
            preferredPeripheralIdentifier = nil
            preferences.removeValue(forKey: AppPreferencesKey.preferredPeripheralIdentifier)
        }

        if selectedMugIdentifier == identifier {
            let nextIdentifier = connectedSidebarMugs.first?.identifier ?? savedSidebarMugs.first?.identifier
            selectMugIdentifier(nextIdentifier, shouldPersistLegacyPreferred: true)
            restoreSelectedMugState()
        } else {
            refreshDisplayedNamesFromSavedAliases()
        }

        bluetoothCoordinator?.setPreferredPeripheralIdentifier(selectedMugIdentifier ?? preferredPeripheralIdentifier)
        synchronizeAutoConnectIdentifiersWithBluetooth()
        synchronizeIdleSleepPrevention()
    }

    func selectSidebarMug(identifier: String) {
        guard allSidebarMugIdentifiers.contains(identifier) else {
            AppLog.sidebar.debug("Ignored sidebar selection for unknown mug \(identifier, privacy: .private)")
            return
        }

        let previousSelection = selectedMugIdentifier
        guard previousSelection != identifier else {
            AppLog.sidebar.info("Ignored repeated sidebar selection for \(identifier, privacy: .private)")
            return
        }

        AppLog.sidebar.info(
            "Selected sidebar mug previous=\(previousSelection ?? "none", privacy: .private) next=\(identifier, privacy: .private)"
        )

        selectMugIdentifier(identifier, shouldPersistLegacyPreferred: true)
        restoreSelectedMugState()

        if let mug = discoveredMugs.first(where: { $0.identifier == identifier }) {
            chooseDiscoveredMug(mug)
            return
        }

        bluetoothCoordinator?.setPreferredPeripheralIdentifier(identifier)

        let knownName = savedName(for: identifier)
        deviceName = knownName
        preferences.set(knownName, forKey: AppPreferencesKey.lastKnownDeviceName)

        if canStartPreferredScan(for: identifier) {
            AppLog.sidebar.info("Starting preferred mug scan after sidebar selection for \(identifier, privacy: .private)")
            bluetoothCoordinator?.scanForPreferredMug()
        }
    }

    func scanForNearbyMugs() {
        guard canTriggerSidebarScan else { return }

        switch connectionState {
        case .permissionNeeded:
            SystemSettingsNavigator.openBluetoothPrivacy()
        default:
            bluetoothCoordinator?.retryScan()
        }
    }

    private func startDiscoveryScanIfNeeded() {
        guard isDiscoveryWindowOpen, canOpenDiscoveryWindow else { return }
        bluetoothCoordinator?.startDiscoveryScan(excluding: Array(discoveryExcludedMugIdentifiers))
    }

    func beginEditingCurrentMugName() {
        guard canEditCurrentMugName, let activePeripheralIdentifier else { return }
        mugNameEditingIdentifier = activePeripheralIdentifier
        mugNameDraft = editableMugName(for: activePeripheralIdentifier)
        isPresentingMugNameSheet = true
    }

    func beginEditingSidebarMugName(identifier: String) {
        guard sidebarMugs.contains(where: { $0.identifier == identifier }) else { return }

        mugNameEditingIdentifier = identifier
        sidebarMugNameEditingIdentifier = identifier
        sidebarMugNameDraft = editableMugName(for: identifier)
    }

    func cancelEditingCurrentMugName() {
        isPresentingMugNameSheet = false
        mugNameDraft = ""
        mugNameEditingIdentifier = nil
    }

    func saveCurrentMugName() {
        guard let identifier = mugNameEditingIdentifier ?? activePeripheralIdentifier else { return }

        let trimmedName = Self.limitedMugName(mugNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmedName.isEmpty else { return }

        saveMugName(trimmedName, for: identifier)
        isPresentingMugNameSheet = false
        mugNameDraft = ""
        mugNameEditingIdentifier = nil
    }

    func commitSidebarMugNameRename() {
        guard let identifier = sidebarMugNameEditingIdentifier else { return }

        let trimmedName = Self.limitedMugName(sidebarMugNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmedName.isEmpty else {
            cancelSidebarMugNameRename()
            return
        }

        saveMugName(trimmedName, for: identifier)
        cancelSidebarMugNameRename()
    }

    func cancelSidebarMugNameRename() {
        sidebarMugNameEditingIdentifier = nil
        sidebarMugNameDraft = ""
        if !isPresentingMugNameSheet {
            mugNameEditingIdentifier = nil
        }
    }

    func removeCurrentMugName() {
        guard let identifier = mugNameEditingIdentifier ?? activePeripheralIdentifier else { return }
        savedMugNamesByIdentifier.removeValue(forKey: identifier)
        persistSavedMugNames()
        refreshDisplayedNamesFromSavedAliases()
        if identifier == activePeripheralIdentifier {
            preferences.set(deviceName, forKey: AppPreferencesKey.lastKnownDeviceName)
        }
    }

    func refreshReadings() {
        guard canRefreshReadings else { return }
        bluetoothCoordinator?.refreshReadings(for: selectedMugIdentifier ?? activePeripheralIdentifier)
    }

    func setTargetTemperatureNotificationsEnabled(_ isEnabled: Bool) {
        setNotificationPreference(.targetTemperature, isEnabled: isEnabled)
    }

    func setBatteryFullyChargedNotificationsEnabled(_ isEnabled: Bool) {
        setNotificationPreference(.batteryFullyCharged, isEnabled: isEnabled)
    }

    func setBatteryFullyDischargedNotificationsEnabled(_ isEnabled: Bool) {
        setNotificationPreference(.batteryFullyDischarged, isEnabled: isEnabled)
    }

    func setSoundsEnabled(_ isEnabled: Bool) {
        soundsEnabled = isEnabled
    }

    func setLaunchesAtLogin(_ isEnabled: Bool) {
        guard isEnabled != launchesAtLogin else { return }

        do {
            try loginItemManager.setEnabled(isEnabled)
            refreshLaunchAtLoginStatus()

            if isEnabled && !launchesAtLogin {
                presentLoginItemApprovalAlertIfNeeded()
            }
        } catch {
            refreshLaunchAtLoginStatus()
            AppLog.settings.error("Failed to update the launch-at-login setting: \(error.localizedDescription, privacy: .private)")

            if loginItemManager.status == .requiresApproval {
                presentLoginItemApprovalAlertIfNeeded()
            } else {
                loginItemAlertTitle = "Couldn’t update login setting"
                loginItemAlertMessage = "Swiftea couldn’t change this macOS setting. Please try again."
                loginItemAlertOffersSystemSettings = false
                isPresentingLoginItemAlert = true
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchesAtLogin = loginItemManager.status == .enabled
    }

    func openLoginItemsSettings() {
        loginItemManager.openSystemSettings()
    }

    func openNotificationSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
            URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        ]

        for url in urls.compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func choosePreset(_ preset: Preset) {
        setTargetTemperatureDraft(toCelsius: preset.celsius, reenableIfNeeded: true)
        commitTargetTemperatureDraft()
    }

    func increaseTemperatureDraft() {
        setTargetTemperatureDraft(toDisplayValue: targetTemperatureDisplayValue + 1, reenableIfNeeded: true)
        queueTargetTemperatureCommit()
    }

    func decreaseTemperatureDraft() {
        setTargetTemperatureDraft(toDisplayValue: targetTemperatureDisplayValue - 1, reenableIfNeeded: true)
        queueTargetTemperatureCommit()
    }

    func setTargetTemperatureDraft(to value: Double, reenableIfNeeded: Bool = false) {
        setTargetTemperatureDraft(toCelsius: value, reenableIfNeeded: reenableIfNeeded)
    }

    func setTargetTemperatureDraft(toCelsius value: Double, reenableIfNeeded: Bool = false) {
        setNormalizedTargetTemperatureDraft(
            Self.normalizedTargetTemperatureCelsius(value, displayUnit: temperatureUnitPreference),
            reenableIfNeeded: reenableIfNeeded
        )
    }

    func beginTargetTemperatureEditing() {
        isEditingTargetTemperature = true
    }

    func setTemperatureControlEnabled(
        _ isEnabled: Bool,
        emptyMugAlertPresentation: EmptyHeatingAlertPresentation = .mainWindow
    ) {
        guard canAdjustTemperature else { return }

        if isEnabled {
            guard !presentEmptyHeatingAlertIfNeeded(on: emptyMugAlertPresentation) else { return }
            setTemperatureControlStateLocally(isEnabled: true)
        } else {
            cancelPendingTargetTemperatureCommit()
            isEditingTargetTemperature = false
            setTemperatureControlStateLocally(isEnabled: false)
        }

        queueTemperatureControlCommit()
    }

    func confirmEmptyHeatingAlert() {
        setEmptyHeatingAlertPresentation(nil)
        guard canAdjustTemperature else { return }
        setTemperatureControlStateLocally(isEnabled: true)
        queueTemperatureControlCommit()
    }

    func cancelEmptyHeatingAlert() {
        setEmptyHeatingAlertPresentation(nil)
    }

    func turnTemperatureControlOff() {
        guard canAdjustTemperature else { return }
        cancelPendingTargetTemperatureCommit()
        isEditingTargetTemperature = false
        setTemperatureControlStateLocally(isEnabled: false)
        commitTemperatureControlState()
    }

    func endTargetTemperatureEditing() {
        isEditingTargetTemperature = false
        commitTargetTemperatureDraft()
    }

    func commitTargetTemperatureDraft() {
        cancelPendingTargetTemperatureCommit()
        guard canAdjustTemperature else { return }
        guard !presentEmptyHeatingAlertIfNeeded(on: .mainWindow) else { return }
        turnTemperatureControlOn()
    }

    func apply(snapshot: BluetoothRuntimeSnapshot) {
        let snapshotReceivedAt = nowProvider()

        guard let mugIdentifier = snapshot.activePeripheralIdentifier else {
            applyGlobalSnapshot(snapshot, timestamp: snapshotReceivedAt)
            return
        }

        ensureMugSession(identifier: mugIdentifier, snapshot: snapshot)

        if let existingIdentifier = duplicateMugIdentifier(forSerialNumber: snapshot.serialNumber, excluding: mugIdentifier) {
            if pendingDiscoveryConnectionIdentifiers.contains(mugIdentifier) {
                discardDuplicateMugSession(identifier: mugIdentifier, duplicateOf: existingIdentifier)
                return
            }

            if pendingDiscoveryConnectionIdentifiers.contains(existingIdentifier) {
                discardDuplicateMugSession(identifier: existingIdentifier, duplicateOf: mugIdentifier)
            } else {
                discardDuplicateMugSession(identifier: mugIdentifier, duplicateOf: existingIdentifier)
                return
            }
        }

        if selectedMugIdentifier == nil {
            selectMugIdentifier(mugIdentifier, shouldPersistLegacyPreferred: true)
        }
        if snapshot.discoveryPhase == .connected {
            addSavedMugIdentifier(mugIdentifier)
        }

        sideEffectMugIdentifierOverride = mugIdentifier
        loadMugSessionState(identifier: mugIdentifier)
        applySingleMugSnapshot(snapshot, snapshotReceivedAt: snapshotReceivedAt)
        evaluateTargetTemperatureNotification(
            mugIdentifier: mugIdentifier,
            isConnected: snapshot.discoveryPhase == .connected
        )
        evaluateBatteryNotifications(
            mugIdentifier: mugIdentifier,
            isConnected: snapshot.discoveryPhase == .connected
        )
        saveCurrentStateToMugSession(identifier: mugIdentifier)
        sideEffectMugIdentifierOverride = nil

        selectConnectedDashboardMugIfNeeded()
        restoreSelectedMugState()
        reconnectAfterLostConnectionIfNeeded(for: mugIdentifier, snapshot: snapshot)
    }

    private func applySingleMugSnapshot(_ snapshot: BluetoothRuntimeSnapshot, snapshotReceivedAt: Date) {
        let previousIsEmpty = isEmpty
        let isConnected = snapshot.discoveryPhase == .connected
        let batteryTrustResult = trustedBatteryLevel(
            reportedLevel: snapshot.batteryLevel,
            mugIdentifier: snapshot.activePeripheralIdentifier ?? activePeripheralIdentifier ?? preferredPeripheralIdentifier,
            isConnected: isConnected,
            isCharging: snapshot.isCharging,
            batteryReadAt: snapshot.lastBatteryReadingAt,
            timestamp: snapshotReceivedAt
        )

        activePeripheralIdentifier = snapshot.activePeripheralIdentifier
        bluetoothAccessLabel = snapshot.authorization.title
        bluetoothHardwareLabel = snapshot.hardwareState.title
        discoveryLabel = snapshot.discoveryPhase.title
        rawDiscoveredMugs = snapshot.discoveredMugs
        deviceFinish = snapshot.discoveredDeviceFinish
        deviceSize = snapshot.discoveredDeviceSize
        deviceSerialNumber = snapshot.serialNumber
        deviceBluetoothName = snapshot.discoveredDeviceName
        lastDiscoveryDetail = snapshot.detailMessage
        currentTemperatureCelsius = snapshot.currentTemperatureCelsius
        batteryLevel = batteryTrustResult.level
        isCharging = snapshot.isCharging
        contentsLevelRaw = snapshot.contentsLevelRaw
        liquidStateDescription = snapshot.liquidStateDescription
        isEmpty = snapshot.isEmpty
        canReadCurrentTemperature = snapshot.canReadCurrentTemperature
        canReadTargetTemperature = snapshot.canReadTargetTemperature
        canReadBattery = snapshot.canReadBattery
        canReadContents = snapshot.canReadContents
        canReadActivity = snapshot.canReadActivity
        canWriteTargetTemperature = snapshot.canWriteTargetTemperature

        if isConnected {
            beginInitialHeatingSafetyIfNeeded(for: snapshot.activePeripheralIdentifier)
        }

        let didBecomeEmpty = previousIsEmpty != true && snapshot.isEmpty == true
        let didBecomeNotEmpty = previousIsEmpty == true && snapshot.isEmpty == false
        let didReceiveInitialFullMugDecision = isAwaitingInitialContentsDecision && snapshot.isEmpty == false

        if didBecomeEmpty {
            emptyHeatingAlertPresentation = nil
            isAwaitingInitialContentsDecision = false

            if !isTemperatureControlOff {
                automaticallyTurnHeatingOffForEmptyMug(
                    canWriteTargetTemperature: snapshot.canWriteTargetTemperature,
                    isConnected: isConnected
                )
            }
        }

        rearmStandaloneHeatingForEmptyMugIfNeeded(
            reportedTargetTemperatureCelsius: snapshot.targetTemperatureCelsius,
            canWriteTargetTemperature: snapshot.canWriteTargetTemperature,
            isConnected: isConnected
        )

        if didBecomeNotEmpty || didReceiveInitialFullMugDecision {
            let didResumeHeating = automaticallyTurnHeatingOnForFilledMug(
                canWriteTargetTemperature: snapshot.canWriteTargetTemperature,
                isConnected: isConnected
            )
            if didResumeHeating {
                isAwaitingInitialContentsDecision = false
            }
        }

        if !isConnected {
            cancelPendingTargetTemperatureCommit()
            cancelPendingTemperatureControlCommit()
            pendingHeatingTransition = nil
            localHeatingIntent = nil
            resetInitialHeatingSafety()
        }

        if
            !isEditingTargetTemperature,
            let targetTemperatureCelsius = snapshot.targetTemperatureCelsius,
            !shouldIgnoreTargetReadBack(targetTemperatureCelsius)
        {
            applyTargetTemperatureReadBack(targetTemperatureCelsius)
        }

        if let discoveredDeviceName = snapshot.discoveredDeviceName {
            preferences.set(displayName(for: discoveredDeviceName, identifier: snapshot.activePeripheralIdentifier), forKey: AppPreferencesKey.lastKnownDeviceName)
        }

        refreshDisplayedNamesFromSavedAliases()

        lastConnectedAtLabel = Self.timestampLabel(for: snapshot.lastConnectedAt, empty: "No mug connected yet")
        lastReadingAtLabel = Self.timestampLabel(for: snapshot.lastReadingAt, empty: "No live readings yet")
        lastTargetWriteAtLabel = Self.timestampLabel(for: snapshot.lastTargetWriteAt, empty: "No target changes yet")

        switch snapshot.authorization {
        case .denied, .restricted:
            connectionState = .permissionNeeded
            statusMessage = "Bluetooth access is required before Swiftea can look for your Ember Mug 2."
            recordHistoryIfNeeded(
                from: snapshot,
                timestamp: snapshotReceivedAt,
                kindOverride: batteryTrustResult.historyKindOverride
            )
            return
        case .allowed, .notDetermined:
            break
        }

        switch snapshot.hardwareState {
        case .unknown, .resetting:
            connectionState = .starting
            statusMessage = snapshot.detailMessage
        case .unsupported:
            connectionState = .bluetoothUnavailable
            statusMessage = "This Mac does not support the Bluetooth features Swiftea needs."
        case .unauthorized:
            connectionState = .permissionNeeded
            statusMessage = "Bluetooth access is blocked for Swiftea."
        case .poweredOff:
            connectionState = .bluetoothUnavailable
            statusMessage = "Bluetooth is off. Turn it on to find your Ember Mug 2."
        case .poweredOn:
            switch snapshot.discoveryPhase {
            case .starting, .idle:
                connectionState = .starting
            case .scanning:
                connectionState = .scanning
            case .choosing:
                connectionState = .choosing
            case .connecting:
                connectionState = .connecting
            case .connected:
                connectionState = .connected
            case .disconnected:
                connectionState = .disconnected
            case .failed:
                connectionState = .error
            }
            statusMessage = snapshot.detailMessage
        }

        recordHistoryIfNeeded(
            from: snapshot,
            timestamp: snapshotReceivedAt,
            kindOverride: batteryTrustResult.historyKindOverride
        )
    }

    static func format(celsius: Double, unit: TemperatureUnitPreference = .celsius) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: unit.measurementUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func formatTime(
        _ date: Date,
        preference: TimeFormatPreference,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = switch preference {
        case .twentyFourHour:
            "HH:mm"
        case .twelveHour:
            "h:mm\na"
        }
        return formatter.string(from: date).lowercased()
    }

    static func timestampLabel(for date: Date?, empty: String) -> String {
        guard let date else { return empty }

        if Calendar.current.isDateInToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func previewConnected() -> AppModel {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        let identifier = "PREVIEW-MUG"
        let mugName = "Sample Mug"
        let bluetoothName = "Ember Mug 2"
        let serialNumber = "SSY00000042"
        let batteryLevel = 0.8
        let currentTemperature = 55.0
        let targetTemperature = Self.normalizedTargetTemperatureCelsius(
            55,
            displayUnit: model.temperatureUnitPreference
        )
        let finish = EmberMugFinish.sandstone
        let size = EmberMugSize.ounce14
        let chartEnd = Self.previewChartEndDate()

        model.connectionState = .connected
        model.activePeripheralIdentifier = identifier
        model.preferredPeripheralIdentifier = identifier
        model.selectedMugIdentifier = identifier
        model.autoConnectMugIdentifiers = [identifier]
        model.chartTimeframePreference = .oneHour
        model.chartNowOverride = chartEnd
        model.statusMessage = "Connected to Ember Mug 2. Live values and target changes can flow through the Bluetooth session."
        model.bluetoothAccessLabel = "Allowed"
        model.bluetoothHardwareLabel = "Powered on"
        model.discoveryLabel = "Connected"
        model.lastDiscoveryDetail = "Connected. Live mug values are updating."
        model.lastConnectedAtLabel = "Today at 9:41 AM"
        model.lastReadingAtLabel = "Today at 9:43 AM"
        model.lastTargetWriteAtLabel = "Today at 9:42 AM"
        model.deviceBluetoothName = bluetoothName
        model.deviceName = mugName
        model.deviceFinish = finish
        model.deviceSize = size
        model.deviceSerialNumber = serialNumber
        model.currentTemperatureCelsius = currentTemperature
        model.targetTemperatureDraftCelsius = targetTemperature
        model.targetTemperatureDraftsByMug[identifier] = targetTemperature
        model.batteryLevel = batteryLevel
        model.isCharging = true
        model.contentsLevelRaw = 30
        model.liquidStateDescription = "Holding temperature"
        model.isEmpty = false
        model.isTemperatureControlOff = false
        model.canReadCurrentTemperature = true
        model.canReadTargetTemperature = true
        model.canReadBattery = true
        model.canReadContents = true
        model.canReadActivity = true
        model.canWriteTargetTemperature = true
        model.savedMugNamesByIdentifier = [
            identifier: mugName,
            "PREVIEW-SAVED-1": "Kitchen Mug",
            "PREVIEW-SAVED-2": "Office Mug",
            "PREVIEW-SAVED-3": "Travel Mug"
        ]
        let historySamples: [(minute: Int, batteryPercent: Int, temperatureCelsius: Double)] = [
            (0, 50, 30),
            (2, 51, 35),
            (4, 52, 40),
            (6, 53, 45),
            (8, 54, 50),
            (10, 55, 55),
            (20, 60, 55),
            (30, 65, 55),
            (40, 70, 55),
            (50, 75, 55),
            (60, Int((batteryLevel * 100).rounded()), currentTemperature)
        ]
        let chartStart = chartEnd.addingTimeInterval(-model.chartTimeframePreference.duration)
        model.mugHistoryEvents = historySamples.map { sample in
            return MugHistoryEvent(
                timestamp: chartStart.addingTimeInterval(TimeInterval(sample.minute * 60)),
                mugIdentifier: identifier,
                appSessionID: model.appSessionID,
                kind: sample.minute == 0 ? .connected : .reading,
                batteryPercent: sample.batteryPercent,
                temperatureCelsius: sample.temperatureCelsius,
                isHeatingOn: true,
                isConnected: true
            )
        }
        model.saveCurrentStateToMugSession(identifier: identifier)
        model.refreshDisplayedNamesFromSavedAliases()
        return model
    }

    private static func previewChartEndDate() -> Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .hour, value: 16, to: startOfToday)
            ?? Date(timeIntervalSince1970: 0).addingTimeInterval(16 * 60 * 60)
    }

    func selectDefaultSidebarMugIfNeeded() {
        selectConnectedDashboardMugIfNeeded()
        guard selectedMugIdentifier == nil else { return }
        guard let identifier = defaultSidebarSelectionIdentifier else { return }
        selectSidebarMug(identifier: identifier)
    }

    private func ensureMugSession(identifier: String, snapshot: BluetoothRuntimeSnapshot? = nil) {
        guard mugSessionsByIdentifier[identifier] == nil else { return }

        var session = MugSessionState(identifier: identifier)
        session.deviceName = snapshot?.discoveredDeviceName
            ?? savedMugNamesByIdentifier[identifier]
            ?? deviceName
        session.deviceBluetoothName = snapshot?.discoveredDeviceName
        session.deviceFinish = snapshot?.discoveredDeviceFinish
        session.deviceSize = snapshot?.discoveredDeviceSize
        session.targetTemperatureDraftCelsius = targetTemperatureDraftsByMug[identifier]
            ?? targetTemperatureDraftCelsius
        mugSessionsByIdentifier[identifier] = session
    }

    private func loadMugSessionState(identifier: String) {
        ensureMugSession(identifier: identifier)
        guard let session = mugSessionsByIdentifier[identifier] else { return }

        connectionState = session.connectionState
        activePeripheralIdentifier = session.activePeripheralIdentifier
        deviceName = displayName(for: session.deviceBluetoothName ?? session.deviceName, identifier: identifier)
        deviceBluetoothName = session.deviceBluetoothName
        deviceFinish = session.deviceFinish
        deviceSize = session.deviceSize
        deviceSerialNumber = session.deviceSerialNumber
        currentTemperatureCelsius = session.currentTemperatureCelsius
        isTemperatureControlOff = session.isTemperatureControlOff
        emptyHeatingAlertPresentation = session.emptyHeatingAlertPresentation
        targetTemperatureDraftCelsius = session.targetTemperatureDraftCelsius
        batteryLevel = session.batteryLevel
        isCharging = session.isCharging
        contentsLevelRaw = session.contentsLevelRaw
        liquidStateDescription = session.liquidStateDescription
        isEmpty = session.isEmpty
        statusMessage = session.statusMessage
        discoveryLabel = session.discoveryLabel
        lastConnectedAtLabel = session.lastConnectedAtLabel
        lastReadingAtLabel = session.lastReadingAtLabel
        lastTargetWriteAtLabel = session.lastTargetWriteAtLabel
        lastDiscoveryDetail = session.lastDiscoveryDetail
        canReadCurrentTemperature = session.canReadCurrentTemperature
        canReadTargetTemperature = session.canReadTargetTemperature
        canReadBattery = session.canReadBattery
        canReadContents = session.canReadContents
        canReadActivity = session.canReadActivity
        canWriteTargetTemperature = session.canWriteTargetTemperature
    }

    private func saveCurrentStateToMugSession(identifier: String) {
        var session = mugSessionsByIdentifier[identifier] ?? MugSessionState(identifier: identifier)
        session.connectionState = connectionState
        session.activePeripheralIdentifier = activePeripheralIdentifier
        session.deviceName = deviceName
        session.deviceBluetoothName = deviceBluetoothName
        session.deviceFinish = deviceFinish
        session.deviceSize = deviceSize
        session.deviceSerialNumber = deviceSerialNumber
        session.currentTemperatureCelsius = currentTemperatureCelsius
        session.isTemperatureControlOff = isTemperatureControlOff
        session.emptyHeatingAlertPresentation = emptyHeatingAlertPresentation
        session.targetTemperatureDraftCelsius = targetTemperatureDraftCelsius
        session.batteryLevel = batteryLevel
        session.isCharging = isCharging
        session.contentsLevelRaw = contentsLevelRaw
        session.liquidStateDescription = liquidStateDescription
        session.isEmpty = isEmpty
        session.statusMessage = statusMessage
        session.discoveryLabel = discoveryLabel
        session.lastConnectedAtLabel = lastConnectedAtLabel
        session.lastReadingAtLabel = lastReadingAtLabel
        session.lastTargetWriteAtLabel = lastTargetWriteAtLabel
        session.lastDiscoveryDetail = lastDiscoveryDetail
        session.canReadCurrentTemperature = canReadCurrentTemperature
        session.canReadTargetTemperature = canReadTargetTemperature
        session.canReadBattery = canReadBattery
        session.canReadContents = canReadContents
        session.canReadActivity = canReadActivity
        session.canWriteTargetTemperature = canWriteTargetTemperature
        mugSessionsByIdentifier[identifier] = session
        synchronizeIdleSleepPrevention()
        if targetTemperatureDraftsByMug[identifier] != targetTemperatureDraftCelsius {
            targetTemperatureDraftsByMug[identifier] = targetTemperatureDraftCelsius
            persistTargetTemperatureDraftsByMug()
        }
    }

    private func restoreSelectedMugState() {
        guard let selectedMugIdentifier else { return }
        ensureMugSession(identifier: selectedMugIdentifier)
        sideEffectMugIdentifierOverride = selectedMugIdentifier
        loadMugSessionState(identifier: selectedMugIdentifier)
        sideEffectMugIdentifierOverride = nil
    }

    private func markMugDisconnectedLocally(identifier: String, detailMessage: String) {
        guard var session = mugSessionsByIdentifier[identifier] else { return }
        addSavedMugIdentifier(identifier)
        session.connectionState = .disconnected
        session.activePeripheralIdentifier = nil
        session.currentTemperatureCelsius = nil
        session.batteryLevel = nil
        session.isCharging = false
        session.contentsLevelRaw = nil
        session.liquidStateDescription = nil
        session.isEmpty = nil
        session.emptyHeatingAlertPresentation = nil
        session.statusMessage = "Not connected."
        session.discoveryLabel = "Disconnected"
        session.lastDiscoveryDetail = detailMessage
        session.canReadCurrentTemperature = false
        session.canReadTargetTemperature = false
        session.canReadBattery = false
        session.canReadContents = false
        session.canReadActivity = false
        session.canWriteTargetTemperature = false
        mugSessionsByIdentifier[identifier] = session
        removeRuntimeState(for: identifier)
        synchronizeIdleSleepPrevention()
    }

    private func removeRuntimeState(for identifier: String) {
        pendingHeatingTransitionByMug.removeValue(forKey: identifier)
        localHeatingIntentByMug.removeValue(forKey: identifier)
        pendingStandaloneHeatingRearmTargetByMug.removeValue(forKey: identifier)
        pendingTargetTemperatureCommitTaskByMug[identifier]?.cancel()
        pendingTargetTemperatureCommitTaskByMug.removeValue(forKey: identifier)
        pendingTemperatureControlCommitTaskByMug[identifier]?.cancel()
        pendingTemperatureControlCommitTaskByMug.removeValue(forKey: identifier)
        initialHeatingSafetyByMug.removeValue(forKey: identifier)
        editingTargetTemperatureMugIdentifiers.remove(identifier)
        lastTrustedBatteryReadingByMug.removeValue(forKey: identifier)
        pendingBatteryReadingByMug.removeValue(forKey: identifier)
        lastProcessedBatteryReadingAtByMug.removeValue(forKey: identifier)
    }

    private func clearActiveMugStateAfterForget() {
        activePeripheralIdentifier = nil
        deviceBluetoothName = nil
        deviceFinish = nil
        deviceSize = nil
        deviceSerialNumber = nil
        currentTemperatureCelsius = nil
        batteryLevel = nil
        isCharging = false
        contentsLevelRaw = nil
        liquidStateDescription = nil
        isEmpty = nil
        canReadCurrentTemperature = false
        canReadTargetTemperature = false
        canReadBattery = false
        canReadContents = false
        canReadActivity = false
        canWriteTargetTemperature = false
    }

    private func selectConnectedDashboardMugIfNeeded() {
        if
            let selectedMugIdentifier,
            shouldKeepSelectedMug(identifier: selectedMugIdentifier)
        {
            return
        }

        guard let connectedIdentifier = connectedSidebarMugs.first?.identifier else { return }
        selectMugIdentifier(connectedIdentifier, shouldPersistLegacyPreferred: true)
    }

    private func applyGlobalSnapshot(_ snapshot: BluetoothRuntimeSnapshot, timestamp: Date) {
        bluetoothAccessLabel = snapshot.authorization.title
        bluetoothHardwareLabel = snapshot.hardwareState.title
        discoveryLabel = snapshot.discoveryPhase.title
        rawDiscoveredMugs = snapshot.discoveredMugs
        lastDiscoveryDetail = snapshot.detailMessage
        refreshDisplayedNamesFromSavedAliases()

        if selectedMugIdentifier == nil || snapshot.authorization == .denied || snapshot.authorization == .restricted {
            activePeripheralIdentifier = nil
            currentTemperatureCelsius = nil
            batteryLevel = nil
            isCharging = false
            contentsLevelRaw = nil
            liquidStateDescription = nil
            isEmpty = nil
            canReadCurrentTemperature = false
            canReadTargetTemperature = false
            canReadBattery = false
            canReadContents = false
            canReadActivity = false
            canWriteTargetTemperature = false

            switch snapshot.authorization {
            case .denied, .restricted:
                connectionState = .permissionNeeded
                statusMessage = "Bluetooth access is required before Swiftea can look for your Ember Mug 2."
            case .allowed, .notDetermined:
                connectionState = connectionState(for: snapshot)
                statusMessage = snapshot.detailMessage
            }
        }
    }

    private func connectionState(for snapshot: BluetoothRuntimeSnapshot) -> ConnectionState {
        switch snapshot.hardwareState {
        case .unknown, .resetting:
            return .starting
        case .unsupported, .poweredOff:
            return .bluetoothUnavailable
        case .unauthorized:
            return .permissionNeeded
        case .poweredOn:
            switch snapshot.discoveryPhase {
            case .starting, .idle:
                return .starting
            case .scanning:
                return .scanning
            case .choosing:
                return .choosing
            case .connecting:
                return .connecting
            case .connected:
                return .connected
            case .disconnected:
                return .disconnected
            case .failed:
                return .error
            }
        }
    }

    private func selectMugIdentifier(_ identifier: String?, shouldPersistLegacyPreferred: Bool) {
        selectedMugIdentifier = identifier
        preferredPeripheralIdentifier = identifier

        if let identifier {
            ensureMugSession(identifier: identifier)
            if shouldPersistLegacyPreferred {
                preferences.set(identifier, forKey: AppPreferencesKey.preferredPeripheralIdentifier)
            }
        } else if shouldPersistLegacyPreferred {
            preferences.removeValue(forKey: AppPreferencesKey.preferredPeripheralIdentifier)
        }
    }

    private func addAutoConnectMugIdentifier(_ identifier: String) {
        guard !autoConnectMugIdentifiers.contains(identifier) else { return }
        addSavedMugIdentifier(identifier)
        autoConnectMugIdentifiers = Array((autoConnectMugIdentifiers + [identifier]).prefix(EmberMugBluetoothCoordinator.maximumSimultaneousMugs))
        synchronizeAutoConnectIdentifiersWithBluetooth()
    }

    private func removeAutoConnectMugIdentifier(_ identifier: String) {
        autoConnectMugIdentifiers.removeAll { $0 == identifier }
        synchronizeAutoConnectIdentifiersWithBluetooth()
    }

    private var reconnectEligibleAutoConnectMugIdentifiers: [String] {
        autoConnectMugIdentifiers.filter { !manuallyDisconnectedMugIdentifiers.contains($0) }
    }

    private func synchronizeAutoConnectIdentifiersWithBluetooth() {
        bluetoothCoordinator?.setAutoConnectPeripheralIdentifiers(reconnectEligibleAutoConnectMugIdentifiers)
    }

    private func markManualDisconnectSuppression(for identifier: String) {
        guard manuallyDisconnectedMugIdentifiers.insert(identifier).inserted else { return }
        persistManuallyDisconnectedMugIdentifiers()
    }

    private func clearManualDisconnectSuppression(for identifier: String) {
        guard manuallyDisconnectedMugIdentifiers.remove(identifier) != nil else { return }
        persistManuallyDisconnectedMugIdentifiers()
    }

    private func addSavedMugIdentifier(_ identifier: String) {
        guard !savedMugIdentifiers.contains(identifier) else { return }
        savedMugIdentifiers.append(identifier)
    }

    private func removeSavedMugIdentifier(_ identifier: String) {
        savedMugIdentifiers.removeAll { $0 == identifier }
    }

    private func uniqueIdentifiers(_ identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        return identifiers.filter { identifier in
            seen.insert(identifier).inserted
        }
    }

    private func orderedKnownMugIdentifiers() -> [String] {
        var ordered: [String] = []

        func append(_ identifier: String?) {
            guard let identifier, !ordered.contains(identifier) else { return }
            ordered.append(identifier)
        }

        append(selectedMugIdentifier)
        append(activePeripheralIdentifier)
        for identifier in autoConnectMugIdentifiers {
            append(identifier)
        }
        for identifier in savedMugIdentifiers {
            append(identifier)
        }
        for identifier in mugSessionsByIdentifier.keys.sorted() {
            append(identifier)
        }
        for identifier in savedMugNamesByIdentifier.keys.sorted() {
            append(identifier)
        }
        append(preferredPeripheralIdentifier)

        return ordered
    }

    private var connectedOrConnectingMugCount: Int {
        mugSessionsByIdentifier.values.filter { session in
            session.connectionState == .connected || session.connectionState == .connecting
        }.count
    }

    private var hasConnectedMugSession: Bool {
        mugSessionsByIdentifier.values.contains { session in
            session.connectionState == .connected
        }
    }

    private func synchronizeIdleSleepPrevention() {
        idleSleepPreventionManager.setIdleSleepPreventionEnabled(hasConnectedMugSession)
    }

    private func isDashboardConnected(_ session: MugSessionState?) -> Bool {
        guard let session else { return false }
        return session.connectionState == .connected && session.hasLiveDashboardData
    }

    private func sidebarSubtitle(for session: MugSessionState) -> String {
        switch session.connectionState {
        case .connected:
            if session.isEmpty == true {
                return "Empty"
            }
            return session.isTemperatureControlOff ? "Off" : "Heating"
        case .connecting:
            return "Connecting"
        case .scanning, .choosing:
            return "Looking"
        case .permissionNeeded:
            return "Bluetooth permission needed"
        case .bluetoothUnavailable:
            return "Bluetooth unavailable"
        case .starting:
            return "Preparing"
        case .disconnected, .error:
            return "Disconnected"
        }
    }

    private func isSavedMugIdentifier(_ identifier: String) -> Bool {
        savedMugIdentifiers.contains(identifier)
            || autoConnectMugIdentifiers.contains(identifier)
            || savedMugNamesByIdentifier[identifier] != nil
            || preferredPeripheralIdentifier == identifier
    }

    private func canStartPreferredScan(for identifier: String) -> Bool {
        switch mugSessionsByIdentifier[identifier]?.connectionState {
        case .connected, .connecting, .scanning, .choosing, .starting:
            return false
        case .permissionNeeded, .bluetoothUnavailable, .disconnected, .error, nil:
            return true
        }
    }

    private func reconnectAfterLostConnectionIfNeeded(
        for identifier: String,
        snapshot: BluetoothRuntimeSnapshot
    ) {
        guard snapshot.discoveryPhase == .disconnected else { return }
        guard reconnectEligibleAutoConnectMugIdentifiers.contains(identifier) else { return }
        handleReconnectOpportunity()
    }

    private func shouldKeepSelectedMug(identifier: String) -> Bool {
        guard let session = mugSessionsByIdentifier[identifier] else { return false }

        if isDashboardConnected(session) {
            return true
        }

        switch session.connectionState {
        case .starting, .scanning, .choosing, .connecting:
            return true
        case .connected, .permissionNeeded, .bluetoothUnavailable, .disconnected, .error:
            return false
        }
    }

    private var discoveryExcludedMugIdentifiers: Set<String> {
        Set(savedMugIdentifiers)
            .union(autoConnectMugIdentifiers)
            .union(savedMugNamesByIdentifier.keys)
            .union(mugSessionsByIdentifier.keys)
            .union(pendingDiscoveryConnectionIdentifiers)
            .union([selectedMugIdentifier, activePeripheralIdentifier, preferredPeripheralIdentifier].compactMap { $0 })
    }

    private func isDiscoveryExcludedMugIdentifier(_ identifier: String) -> Bool {
        discoveryExcludedMugIdentifiers.contains(identifier)
    }

    private func isDiscoveryExcludedMug(_ mug: BluetoothRuntimeSnapshot.DiscoveredMug) -> Bool {
        isDiscoveryExcludedMugIdentifier(mug.identifier)
            || isLikelyKnownMugDuplicate(mug)
    }

    private func isLikelyKnownMugDuplicate(_ mug: BluetoothRuntimeSnapshot.DiscoveredMug) -> Bool {
        guard let finish = mug.finish, let size = mug.size else { return false }

        return mugSessionsByIdentifier.values.contains { session in
            guard session.connectionState == .connected || session.connectionState == .connecting else {
                return false
            }

            guard session.deviceFinish == finish, session.deviceSize == size else {
                return false
            }

            return Self.normalizedBluetoothName(mug.name) == Self.normalizedBluetoothName(session.deviceBluetoothName ?? session.deviceName)
        }
    }

    private func duplicateMugIdentifier(forSerialNumber serialNumber: String?, excluding identifier: String) -> String? {
        guard let serialNumber, !serialNumber.isEmpty else { return nil }

        return mugSessionsByIdentifier.first { candidateIdentifier, session in
            candidateIdentifier != identifier && session.deviceSerialNumber == serialNumber
        }?.key
    }

    private func discardDuplicateMugSession(identifier: String, duplicateOf existingIdentifier: String) {
        removeAutoConnectMugIdentifier(identifier)
        removeSavedMugIdentifier(identifier)
        pendingDiscoveryConnectionIdentifiers.remove(identifier)
        rawDiscoveredMugs.removeAll { $0.identifier == identifier }
        discoveredMugs.removeAll { $0.identifier == identifier }
        mugSessionsByIdentifier.removeValue(forKey: identifier)
        removeRuntimeState(for: identifier)
        bluetoothCoordinator?.forgetMug(identifier: identifier)
        synchronizeIdleSleepPrevention()

        if selectedMugIdentifier == identifier {
            selectMugIdentifier(existingIdentifier, shouldPersistLegacyPreferred: true)
            restoreSelectedMugState()
        }
    }

    private static func normalizedBluetoothName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func persistSelectedMugIdentifier() {
        if let selectedMugIdentifier {
            preferences.set(selectedMugIdentifier, forKey: AppPreferencesKey.selectedMugIdentifier)
        } else {
            preferences.removeValue(forKey: AppPreferencesKey.selectedMugIdentifier)
        }
    }

    private func persistSavedMugIdentifiers() {
        guard !savedMugIdentifiers.isEmpty else {
            preferences.removeValue(forKey: AppPreferencesKey.savedMugIdentifiers)
            return
        }

        guard
            let data = try? JSONEncoder().encode(SavedMugIdentifiersPayload(identifiers: savedMugIdentifiers)),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }

        preferences.set(jsonString, forKey: AppPreferencesKey.savedMugIdentifiers)
    }

    private func persistAutoConnectMugIdentifiers() {
        guard !autoConnectMugIdentifiers.isEmpty else {
            preferences.removeValue(forKey: AppPreferencesKey.autoConnectMugIdentifiers)
            return
        }

        guard
            let data = try? JSONEncoder().encode(SavedMugIdentifiersPayload(identifiers: autoConnectMugIdentifiers)),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }

        preferences.set(jsonString, forKey: AppPreferencesKey.autoConnectMugIdentifiers)
    }

    private func persistManuallyDisconnectedMugIdentifiers() {
        let identifiers = Array(manuallyDisconnectedMugIdentifiers).sorted()
        guard !identifiers.isEmpty else {
            preferences.removeValue(forKey: AppPreferencesKey.manuallyDisconnectedMugIdentifiers)
            return
        }

        guard
            let data = try? JSONEncoder().encode(SavedMugIdentifiersPayload(identifiers: identifiers)),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }

        preferences.set(jsonString, forKey: AppPreferencesKey.manuallyDisconnectedMugIdentifiers)
    }

    private func persistTargetTemperatureDraftsByMug() {
        guard !targetTemperatureDraftsByMug.isEmpty else {
            preferences.removeValue(forKey: AppPreferencesKey.targetTemperatureDraftsByMug)
            return
        }

        guard
            let data = try? JSONEncoder().encode(TargetTemperatureDraftsPayload(draftsByIdentifier: targetTemperatureDraftsByMug)),
            let jsonString = String(data: data, encoding: .utf8)
        else { return }

        preferences.set(jsonString, forKey: AppPreferencesKey.targetTemperatureDraftsByMug)
    }

    private func restoreSavedPreferences() {
        isRestoringSavedPreferences = true
        defer { isRestoringSavedPreferences = false }

        if let savedDeviceName = preferences.string(forKey: AppPreferencesKey.lastKnownDeviceName) {
            deviceName = savedDeviceName
        }

        let legacyPreferredPeripheralIdentifier = preferences.string(forKey: AppPreferencesKey.preferredPeripheralIdentifier)
        preferredPeripheralIdentifier = legacyPreferredPeripheralIdentifier
        selectedMugIdentifier = preferences.string(forKey: AppPreferencesKey.selectedMugIdentifier)
            ?? legacyPreferredPeripheralIdentifier

        if
            let savedMugNamesJSONString = preferences.string(forKey: AppPreferencesKey.savedMugNames),
            let data = savedMugNamesJSONString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(SavedMugNamesPayload.self, from: data)
        {
            savedMugNamesByIdentifier = payload.namesByIdentifier
        }

        if
            let savedMugIdentifiersJSONString = preferences.string(forKey: AppPreferencesKey.savedMugIdentifiers),
            let data = savedMugIdentifiersJSONString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(SavedMugIdentifiersPayload.self, from: data)
        {
            savedMugIdentifiers = payload.identifiers
        }

        if
            let savedAutoConnectJSONString = preferences.string(forKey: AppPreferencesKey.autoConnectMugIdentifiers),
            let data = savedAutoConnectJSONString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(SavedMugIdentifiersPayload.self, from: data)
        {
            autoConnectMugIdentifiers = Array(payload.identifiers.prefix(EmberMugBluetoothCoordinator.maximumSimultaneousMugs))
        } else if let legacyPreferredPeripheralIdentifier {
            autoConnectMugIdentifiers = [legacyPreferredPeripheralIdentifier]
        }

        if
            let manuallyDisconnectedJSONString = preferences.string(forKey: AppPreferencesKey.manuallyDisconnectedMugIdentifiers),
            let data = manuallyDisconnectedJSONString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(SavedMugIdentifiersPayload.self, from: data)
        {
            manuallyDisconnectedMugIdentifiers = Set(payload.identifiers)
        }

        savedMugIdentifiers = uniqueIdentifiers(
            savedMugIdentifiers
                + autoConnectMugIdentifiers
                + savedMugNamesByIdentifier.keys.sorted()
                + [legacyPreferredPeripheralIdentifier, selectedMugIdentifier].compactMap { $0 }
        )

        if let savedTargetTemperature = preferences.double(forKey: AppPreferencesKey.targetTemperatureDraftCelsius) {
            targetTemperatureDraftCelsius = Self.clampedTargetTemperatureCelsius(savedTargetTemperature)
            hasUserChosenGlobalTargetTemperatureDraft = true
        }

        if
            let savedTargetDraftsJSONString = preferences.string(forKey: AppPreferencesKey.targetTemperatureDraftsByMug),
            let data = savedTargetDraftsJSONString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(TargetTemperatureDraftsPayload.self, from: data)
        {
            targetTemperatureDraftsByMug = payload.draftsByIdentifier.mapValues(Self.clampedTargetTemperatureCelsius)
            userChosenTargetTemperatureDraftIdentifiers = Set(targetTemperatureDraftsByMug.keys)
        }

        if
            let selectedMugIdentifier,
            let selectedDraft = targetTemperatureDraftsByMug[selectedMugIdentifier]
        {
            targetTemperatureDraftCelsius = selectedDraft
        }

        if
            let savedThemePreference = preferences.string(forKey: AppPreferencesKey.themePreference),
            let themePreference = ThemePreference(rawValue: savedThemePreference)
        {
            self.themePreference = themePreference
        }

        if
            let savedTemperatureUnitPreference = preferences.string(forKey: AppPreferencesKey.temperatureUnitPreference),
            let temperatureUnitPreference = TemperatureUnitPreference(rawValue: savedTemperatureUnitPreference)
        {
            self.temperatureUnitPreference = temperatureUnitPreference
        }

        if
            let savedTimeFormatPreference = preferences.string(forKey: AppPreferencesKey.timeFormatPreference),
            let timeFormatPreference = TimeFormatPreference(rawValue: savedTimeFormatPreference)
        {
            self.timeFormatPreference = timeFormatPreference
        }

        if
            let savedChartTimeframePreference = preferences.string(forKey: AppPreferencesKey.chartTimeframePreference),
            let chartTimeframePreference = ChartTimeframePreference(rawValue: savedChartTimeframePreference)
        {
            self.chartTimeframePreference = chartTimeframePreference
        }

        if let savedKeepsRunningWhenWindowClosed = preferences.bool(forKey: AppPreferencesKey.keepsRunningWhenWindowClosed) {
            keepsRunningWhenWindowClosed = savedKeepsRunningWhenWindowClosed
        }

        if
            let savedAppLocationPreference = preferences.string(forKey: AppPreferencesKey.appLocationPreference),
            let appLocationPreference = AppLocationPreference(rawValue: savedAppLocationPreference)
        {
            self.appLocationPreference = appLocationPreference
        }

        if let savedTargetTemperatureNotificationsEnabled = preferences.bool(forKey: AppPreferencesKey.targetTemperatureNotificationsEnabled) {
            targetTemperatureNotificationsEnabled = savedTargetTemperatureNotificationsEnabled
        }
        if let savedBatteryFullyChargedNotificationsEnabled = preferences.bool(forKey: AppPreferencesKey.batteryFullyChargedNotificationsEnabled) {
            batteryFullyChargedNotificationsEnabled = savedBatteryFullyChargedNotificationsEnabled
        }
        if let savedBatteryFullyDischargedNotificationsEnabled = preferences.bool(forKey: AppPreferencesKey.batteryFullyDischargedNotificationsEnabled) {
            batteryFullyDischargedNotificationsEnabled = savedBatteryFullyDischargedNotificationsEnabled
        }
        if let savedSoundsEnabled = preferences.bool(forKey: AppPreferencesKey.soundsEnabled) {
            soundsEnabled = savedSoundsEnabled
        }

        normalizeTargetTemperatureDraftForCurrentUnit()

        for identifier in orderedKnownMugIdentifiers() {
            ensureMugSession(identifier: identifier)
        }
        restoreSelectedMugState()
    }

    private func restoreUpdateChangelogPresentationState() {
        guard !appVersionIdentifier.isEmpty else { return }

        let currentMarketingVersion = AppVersion.marketingVersion(from: appVersionIdentifier)

        if let lastPresentedVersion = preferences.string(forKey: AppPreferencesKey.lastPresentedChangelogVersion) {
            shouldPresentUpdateChangelog = lastPresentedVersion != appVersionIdentifier
            guard shouldPresentUpdateChangelog else { return }

            updateChangelogReleases = PublishedChangelog.releases(
                from: changelogMarkdown,
                newerThan: AppVersion.marketingVersion(from: lastPresentedVersion),
                through: currentMarketingVersion
            )
            return
        }

        if hasExistingInstallPreferencesFootprint() {
            shouldPresentUpdateChangelog = true
            updateChangelogReleases = PublishedChangelog.releases(
                from: changelogMarkdown,
                newerThan: nil,
                through: currentMarketingVersion
            )
            return
        }

        preferences.set(appVersionIdentifier, forKey: AppPreferencesKey.lastPresentedChangelogVersion)
    }

    private func restoreOnboardingPresentationState() {
        if !hasAcceptedCurrentLegalDocuments {
            shouldStartOnboardingAtLegalAgreement = hasExistingInstallPreferencesFootprint()
                || preferences.bool(forKey: AppPreferencesKey.hasCompletedOnboarding) == true
            shouldPresentOnboarding = true
            return
        }

        if let hasCompletedOnboarding = preferences.bool(forKey: AppPreferencesKey.hasCompletedOnboarding) {
            shouldStartOnboardingAtLegalAgreement = false
            shouldPresentOnboarding = !hasCompletedOnboarding
            return
        }

        if hasExistingInstallPreferencesFootprint() {
            preferences.set(true, forKey: AppPreferencesKey.hasCompletedOnboarding)
            shouldStartOnboardingAtLegalAgreement = false
            shouldPresentOnboarding = false
            return
        }

        shouldStartOnboardingAtLegalAgreement = false
        shouldPresentOnboarding = true
    }

    private func hasExistingInstallPreferencesFootprint() -> Bool {
        if preferences.double(forKey: AppPreferencesKey.targetTemperatureDraftCelsius) != nil {
            return true
        }

        let stringKeys = [
            AppPreferencesKey.targetTemperatureDraftsByMug,
            AppPreferencesKey.lastKnownDeviceName,
            AppPreferencesKey.preferredPeripheralIdentifier,
            AppPreferencesKey.selectedMugIdentifier,
            AppPreferencesKey.savedMugIdentifiers,
            AppPreferencesKey.autoConnectMugIdentifiers,
            AppPreferencesKey.manuallyDisconnectedMugIdentifiers,
            AppPreferencesKey.savedMugNames,
            AppPreferencesKey.themePreference,
            AppPreferencesKey.temperatureUnitPreference,
            AppPreferencesKey.timeFormatPreference,
            AppPreferencesKey.chartTimeframePreference,
            AppPreferencesKey.appLocationPreference
        ]

        if stringKeys.contains(where: { preferences.string(forKey: $0) != nil }) {
            return true
        }

        let boolKeys = [
            AppPreferencesKey.keepsRunningWhenWindowClosed,
            AppPreferencesKey.targetTemperatureNotificationsEnabled,
            AppPreferencesKey.batteryFullyChargedNotificationsEnabled,
            AppPreferencesKey.batteryFullyDischargedNotificationsEnabled,
            AppPreferencesKey.soundsEnabled
        ]

        return boolKeys.contains(where: { preferences.bool(forKey: $0) != nil })
    }

    private var targetTemperatureDisplayRange: ClosedRange<Double> {
        Self.targetTemperatureDisplayRange(for: temperatureUnitPreference)
    }

    private var targetTemperatureDisplayValue: Double {
        Self.targetTemperatureDisplayValue(
            forCelsius: targetTemperatureDraftCelsius,
            unit: temperatureUnitPreference
        )
    }

    private func setTargetTemperatureDraft(toDisplayValue value: Double, reenableIfNeeded: Bool = false) {
        setNormalizedTargetTemperatureDraft(
            Self.normalizedTargetTemperatureCelsius(value, sourceUnit: temperatureUnitPreference),
            reenableIfNeeded: reenableIfNeeded
        )
    }

    private func setNormalizedTargetTemperatureDraft(_ celsius: Double, reenableIfNeeded: Bool = false) {
        targetTemperatureDraftCelsius = celsius
        hasUserChosenGlobalTargetTemperatureDraft = true
        if canAdjustTemperature {
            rememberLocalHeatingIntent(expectedTargetTemperatureCelsius: targetTemperatureDraftCelsius)
            startPendingHeatingTransition(expectedTargetTemperatureCelsius: targetTemperatureDraftCelsius)
        }
        if reenableIfNeeded, !shouldRequireEmptyMugHeatingConfirmation {
            isTemperatureControlOff = false
        }
        if let transientMugIdentifier {
            userChosenTargetTemperatureDraftIdentifiers.insert(transientMugIdentifier)
            targetTemperatureDraftsByMug[transientMugIdentifier] = targetTemperatureDraftCelsius
            if var session = mugSessionsByIdentifier[transientMugIdentifier] {
                session.targetTemperatureDraftCelsius = targetTemperatureDraftCelsius
                session.isTemperatureControlOff = isTemperatureControlOff
                mugSessionsByIdentifier[transientMugIdentifier] = session
            }
            persistTargetTemperatureDraftsByMug()
        }
        preferences.set(targetTemperatureDraftCelsius, forKey: AppPreferencesKey.targetTemperatureDraftCelsius)
    }

    private func normalizeTargetTemperatureDraftForCurrentUnit() {
        let normalizedTargetTemperature = Self.normalizedTargetTemperatureCelsius(
            targetTemperatureDraftCelsius,
            displayUnit: temperatureUnitPreference
        )

        if abs(targetTemperatureDraftCelsius - normalizedTargetTemperature) > 0.0001 {
            targetTemperatureDraftCelsius = normalizedTargetTemperature
            if let transientMugIdentifier {
                targetTemperatureDraftsByMug[transientMugIdentifier] = normalizedTargetTemperature
                persistTargetTemperatureDraftsByMug()
            }
            preferences.set(targetTemperatureDraftCelsius, forKey: AppPreferencesKey.targetTemperatureDraftCelsius)
        }
    }

    private static func targetTemperatureDisplayRange(
        for unit: TemperatureUnitPreference
    ) -> ClosedRange<Double> {
        switch unit {
        case .celsius:
            targetTemperatureRangeCelsius
        case .fahrenheit:
            targetTemperatureRangeFahrenheit
        }
    }

    private static func targetTemperatureDisplayValue(
        forCelsius celsius: Double,
        unit: TemperatureUnitPreference
    ) -> Double {
        let clampedCelsius = clampedTargetTemperatureCelsius(celsius)

        let displayValue: Double = switch unit {
        case .celsius:
            clampedCelsius.rounded(.toNearestOrAwayFromZero)
        case .fahrenheit:
            fahrenheit(fromCelsius: clampedCelsius).rounded(.toNearestOrAwayFromZero)
        }

        return clampedTargetTemperatureDisplayValue(displayValue, unit: unit)
    }

    private static func normalizedTargetTemperatureCelsius(
        _ value: Double,
        sourceUnit: TemperatureUnitPreference
    ) -> Double {
        let displayValue = clampedTargetTemperatureDisplayValue(
            value.rounded(.toNearestOrAwayFromZero),
            unit: sourceUnit
        )

        switch sourceUnit {
        case .celsius:
            return displayValue
        case .fahrenheit:
            return celsius(fromFahrenheit: displayValue)
        }
    }

    private static func normalizedTargetTemperatureCelsius(
        _ celsius: Double,
        displayUnit: TemperatureUnitPreference
    ) -> Double {
        let displayValue = targetTemperatureDisplayValue(forCelsius: celsius, unit: displayUnit)
        return normalizedTargetTemperatureCelsius(displayValue, sourceUnit: displayUnit)
    }

    private static func clampedTargetTemperatureCelsius(_ value: Double) -> Double {
        min(max(value, targetTemperatureRangeCelsius.lowerBound), targetTemperatureRangeCelsius.upperBound)
    }

    private static func clampedTargetTemperatureDisplayValue(
        _ value: Double,
        unit: TemperatureUnitPreference
    ) -> Double {
        let range = targetTemperatureDisplayRange(for: unit)
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func celsius(fromFahrenheit fahrenheit: Double) -> Double {
        (fahrenheit - 32) * 5 / 9
    }

    private static func fahrenheit(fromCelsius celsius: Double) -> Double {
        celsius * 9 / 5 + 32
    }

    static func temperatureDisplayValue(
        celsius: Double,
        unit: TemperatureUnitPreference
    ) -> Double {
        switch unit {
        case .celsius:
            celsius
        case .fahrenheit:
            fahrenheit(fromCelsius: celsius)
        }
    }

    private static func formatTargetTemperatureValue(
        _ value: Double,
        unit: TemperatureUnitPreference
    ) -> String {
        let roundedValue = Int(value.rounded(.toNearestOrAwayFromZero))

        switch unit {
        case .celsius:
            return "\(roundedValue)°C"
        case .fahrenheit:
            return "\(roundedValue)°F"
        }
    }

    private func queueTargetTemperatureCommit() {
        cancelPendingTargetTemperatureCommit()

        pendingTargetTemperatureCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingTargetTemperatureCommitTask = nil
            self.commitTargetTemperatureDraft()
        }
    }

    private func cancelPendingTargetTemperatureCommit() {
        pendingTargetTemperatureCommitTask?.cancel()
        pendingTargetTemperatureCommitTask = nil
    }

    private func queueTemperatureControlCommit() {
        cancelPendingTemperatureControlCommit()

        pendingTemperatureControlCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingTemperatureControlCommitTask = nil
            self.commitTemperatureControlState()
        }
    }

    private func cancelPendingTemperatureControlCommit() {
        pendingTemperatureControlCommitTask?.cancel()
        pendingTemperatureControlCommitTask = nil
    }

    private func installLifecycleObservers() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppResumed()
            }
        }

        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppResumed()
            }
        }
    }

    private func startLegallyAuthorizedRuntimeIfNeeded() {
        guard startsRuntimeWhenLegallyAuthorized else { return }
        guard hasAcceptedCurrentLegalDocuments else { return }
        guard !hasStartedLegallyAuthorizedRuntime else { return }

        hasStartedLegallyAuthorizedRuntime = true
        installLifecycleObservers()
        loadMugHistoryAndRecordSessionStart()

        if let deferredBluetoothCoordinator {
            bluetoothCoordinator = deferredBluetoothCoordinator
            self.deferredBluetoothCoordinator = nil
            deferredBluetoothCoordinator.setPreferredPeripheralIdentifier(
                selectedMugIdentifier ?? preferredPeripheralIdentifier
            )
            deferredBluetoothCoordinator.setAutoConnectPeripheralIdentifiers(
                reconnectEligibleAutoConnectMugIdentifiers
            )
            deferredBluetoothCoordinator.recoverAutoConnectMugs()
            return
        }

        bluetoothCoordinator = EmberMugBluetoothCoordinator(
            preferredPeripheralIdentifier: selectedMugIdentifier ?? preferredPeripheralIdentifier,
            autoConnectPeripheralIdentifiers: reconnectEligibleAutoConnectMugIdentifiers
        ) { [weak self] snapshot in
            Task { @MainActor in
                self?.apply(snapshot: snapshot)
            }
        }
    }

    private func startPendingHeatingTransition(expectedTargetTemperatureCelsius: Double?) {
        pendingHeatingTransition = PendingHeatingTransition(
            expectedTargetTemperatureCelsius: expectedTargetTemperatureCelsius,
            startedAt: Date()
        )
    }

    private func rememberLocalHeatingIntent(expectedTargetTemperatureCelsius: Double?) {
        localHeatingIntent = LocalHeatingIntent(
            expectedTargetTemperatureCelsius: expectedTargetTemperatureCelsius
        )
    }

    private func shouldIgnoreTargetReadBack(_ targetTemperatureCelsius: Double) -> Bool {
        if let localHeatingIntent {
            if localHeatingIntent.matches(targetTemperatureCelsius) {
                pendingHeatingTransition = nil
                return false
            }

            return true
        }

        guard let pendingHeatingTransition else { return false }

        if Date() >= pendingHeatingTransition.expiresAt {
            self.pendingHeatingTransition = nil
            return false
        }

        if pendingHeatingTransition.matches(targetTemperatureCelsius) {
            self.pendingHeatingTransition = nil
            return false
        }

        return true
    }

    private var shouldRequireEmptyMugHeatingConfirmation: Bool {
        isEmpty == true && isTemperatureControlOff
    }

    private func presentEmptyHeatingAlertIfNeeded(
        on presentation: EmptyHeatingAlertPresentation
    ) -> Bool {
        guard shouldRequireEmptyMugHeatingConfirmation else { return false }
        setEmptyHeatingAlertPresentation(presentation)
        return true
    }

    private func setEmptyHeatingAlertPresentation(_ presentation: EmptyHeatingAlertPresentation?) {
        emptyHeatingAlertPresentation = presentation

        guard
            let transientMugIdentifier,
            var session = mugSessionsByIdentifier[transientMugIdentifier]
        else { return }

        session.emptyHeatingAlertPresentation = presentation
        mugSessionsByIdentifier[transientMugIdentifier] = session
    }

    private func setTemperatureControlStateLocally(isEnabled: Bool) {
        updateTemperatureControlState(isEnabled: isEnabled)
        rememberLocalHeatingIntent(
            expectedTargetTemperatureCelsius: isEnabled ? targetTemperatureDraftCelsius : nil
        )
        startPendingHeatingTransition(
            expectedTargetTemperatureCelsius: isEnabled ? targetTemperatureDraftCelsius : nil
        )
    }

    private func setTemperatureControlStateFromReadBack(isEnabled: Bool) {
        updateTemperatureControlState(isEnabled: isEnabled)
    }

    private func updateTemperatureControlState(isEnabled: Bool) {
        let wasEnabled = !isTemperatureControlOff
        guard wasEnabled != isEnabled else {
            isTemperatureControlOff = !isEnabled
            return
        }

        isTemperatureControlOff = !isEnabled
        if let transientMugIdentifier, var session = mugSessionsByIdentifier[transientMugIdentifier] {
            session.isTemperatureControlOff = isTemperatureControlOff
            session.targetTemperatureDraftCelsius = targetTemperatureDraftCelsius
            mugSessionsByIdentifier[transientMugIdentifier] = session
        }
        if soundsEnabled {
            heatingToggleSoundPlayer.playHeatingToggleSound(isEnabled: isEnabled)
        }
        recordHistoryIfNeeded(kindOverride: .heatingChanged)
    }

    private func commitTemperatureControlState() {
        cancelPendingTemperatureControlCommit()
        guard canAdjustTemperature else { return }

        if isTemperatureControlOff, isEmpty == true {
            return
        }

        bluetoothCoordinator?.setTargetTemperature(
            isTemperatureControlOff ? nil : targetTemperatureDraftCelsius,
            for: transientMugIdentifier
        )
    }

    private func turnTemperatureControlOn() {
        setTemperatureControlStateLocally(isEnabled: true)
        commitTemperatureControlState()
    }

    private func beginInitialHeatingSafetyIfNeeded(for peripheralIdentifier: String?) {
        guard
            initialHeatingSafetyPeripheralIdentifier != peripheralIdentifier
                || !didBeginInitialHeatingSafety
        else { return }

        initialHeatingSafetyPeripheralIdentifier = peripheralIdentifier
        isAwaitingInitialContentsDecision = true
        didBeginInitialHeatingSafety = true
        emptyHeatingAlertPresentation = nil
        isEditingTargetTemperature = false
        cancelPendingTargetTemperatureCommit()
        cancelPendingTemperatureControlCommit()
        setTemperatureControlStateFromReadBack(isEnabled: false)
    }

    private func resetInitialHeatingSafety() {
        initialHeatingSafetyPeripheralIdentifier = nil
        isAwaitingInitialContentsDecision = false
        didBeginInitialHeatingSafety = false
    }

    private func automaticallyTurnHeatingOffForEmptyMug(
        canWriteTargetTemperature: Bool,
        isConnected: Bool
    ) {
        cancelPendingTargetTemperatureCommit()
        cancelPendingTemperatureControlCommit()
        isEditingTargetTemperature = false
        setTemperatureControlStateFromReadBack(isEnabled: false)
    }

    private func automaticallyTurnHeatingOnForFilledMug(
        canWriteTargetTemperature: Bool,
        isConnected: Bool
    ) -> Bool {
        guard isTemperatureControlOff, isConnected, canWriteTargetTemperature else { return false }

        cancelPendingTargetTemperatureCommit()
        cancelPendingTemperatureControlCommit()
        emptyHeatingAlertPresentation = nil
        isEditingTargetTemperature = false
        setTemperatureControlStateLocally(isEnabled: true)
        bluetoothCoordinator?.setTargetTemperature(targetTemperatureDraftCelsius, for: transientMugIdentifier)
        return true
    }

    private func rearmStandaloneHeatingForEmptyMugIfNeeded(
        reportedTargetTemperatureCelsius: Double?,
        canWriteTargetTemperature: Bool,
        isConnected: Bool
    ) {
        guard
            isConnected,
            canWriteTargetTemperature,
            isEmpty == true,
            isTemperatureControlOff,
            let reportedTargetTemperatureCelsius
        else { return }

        guard reportedTargetTemperatureCelsius <= 0.01 else {
            pendingStandaloneHeatingRearmTarget = nil
            return
        }

        guard pendingStandaloneHeatingRearmTarget.map({ abs($0 - targetTemperatureDraftCelsius) < 0.35 }) != true else {
            return
        }

        localHeatingIntent = nil
        pendingHeatingTransition = nil
        pendingStandaloneHeatingRearmTarget = targetTemperatureDraftCelsius
        bluetoothCoordinator?.setTargetTemperature(targetTemperatureDraftCelsius, for: transientMugIdentifier)
    }

    private func applyTargetTemperatureReadBack(_ targetTemperatureCelsius: Double) {
        if targetTemperatureCelsius <= 0.01 {
            setTemperatureControlStateFromReadBack(isEnabled: false)
            return
        }

        if isEmpty == true || isAwaitingInitialContentsDecision {
            pendingStandaloneHeatingRearmTarget = nil
            if !hasUserChosenTargetTemperatureDraftForCurrentMug {
                storeTargetTemperatureDraftFromReadBack(targetTemperatureCelsius)
            }
            setTemperatureControlStateFromReadBack(isEnabled: false)
            return
        }

        storeTargetTemperatureDraftFromReadBack(targetTemperatureCelsius)
        setTemperatureControlStateFromReadBack(isEnabled: true)
    }

    private var hasUserChosenTargetTemperatureDraftForCurrentMug: Bool {
        if let transientMugIdentifier, userChosenTargetTemperatureDraftIdentifiers.contains(transientMugIdentifier) {
            return true
        }

        return hasUserChosenGlobalTargetTemperatureDraft
    }

    private func storeTargetTemperatureDraftFromReadBack(_ targetTemperatureCelsius: Double) {
        targetTemperatureDraftCelsius = Self.normalizedTargetTemperatureCelsius(
            targetTemperatureCelsius,
            displayUnit: temperatureUnitPreference
        )
        if let transientMugIdentifier {
            targetTemperatureDraftsByMug[transientMugIdentifier] = targetTemperatureDraftCelsius
            persistTargetTemperatureDraftsByMug()
        }
    }

    private func loadMugHistoryAndRecordSessionStart() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let loadedEvents = (try? await self.mugHistoryStore.loadEvents()) ?? []
            let locallyRecordedEvents = self.mugHistoryEvents
            let combinedEvents = (loadedEvents + locallyRecordedEvents)
                .reduce(into: [UUID: MugHistoryEvent]()) { result, event in
                    result[event.id] = event
                }
                .values

            self.mugHistoryEvents = MugHistoryRetention.pruned(
                Array(combinedEvents),
                now: self.nowProvider()
            )
            self.recordAppSessionStarted()
        }
    }

    private func recordAppSessionStarted() {
        appendMugHistoryEvent(
            MugHistoryEvent(
                timestamp: nowProvider(),
                mugIdentifier: nil,
                appSessionID: appSessionID,
                kind: .appSessionStarted,
                batteryPercent: nil,
                temperatureCelsius: nil,
                isHeatingOn: nil,
                isConnected: false
            )
        )
    }

    private func trustedBatteryLevel(
        reportedLevel: Double?,
        mugIdentifier: String?,
        isConnected: Bool,
        isCharging: Bool,
        batteryReadAt: Date?,
        timestamp: Date
    ) -> BatteryTrustResult {
        guard isConnected else {
            resetBatteryTrust(for: mugIdentifier)
            return BatteryTrustResult(level: nil, historyKindOverride: nil)
        }

        guard let reportedPercent = Self.batteryPercent(from: reportedLevel) else {
            return BatteryTrustResult(level: nil, historyKindOverride: nil)
        }

        guard let mugIdentifier else {
            return BatteryTrustResult(
                level: Self.batteryLevel(from: reportedPercent),
                historyKindOverride: nil
            )
        }

        if
            let batteryReadAt,
            lastProcessedBatteryReadingAtByMug[mugIdentifier] == batteryReadAt
        {
            return BatteryTrustResult(
                level: lastTrustedBatteryReadingByMug[mugIdentifier].map { Self.batteryLevel(from: $0.percent) }
                    ?? Self.batteryLevel(from: reportedPercent),
                historyKindOverride: nil
            )
        }
        lastProcessedBatteryReadingAtByMug[mugIdentifier] = batteryReadAt ?? timestamp

        guard let trustedReading = lastTrustedBatteryReadingByMug[mugIdentifier] else {
            acceptBatteryReading(reportedPercent, for: mugIdentifier, at: batteryReadAt ?? timestamp)
            return BatteryTrustResult(
                level: Self.batteryLevel(from: reportedPercent),
                historyKindOverride: nil
            )
        }

        let readingTimestamp = batteryReadAt ?? timestamp
        if Self.shouldTrustBatteryChange(
            from: trustedReading,
            to: reportedPercent,
            isCharging: isCharging,
            timestamp: readingTimestamp
        ) {
            acceptBatteryReading(reportedPercent, for: mugIdentifier, at: readingTimestamp)
            return BatteryTrustResult(
                level: Self.batteryLevel(from: reportedPercent),
                historyKindOverride: nil
            )
        }

        let pendingReading = updatedPendingBatteryReading(
            for: mugIdentifier,
            reportedPercent: reportedPercent,
            timestamp: readingTimestamp
        )

        AppLog.bluetooth.notice(
            "Rejected suspicious battery reading \(reportedPercent, privacy: .public)% for mug \(mugIdentifier, privacy: .private); trusted \(trustedReading.percent, privacy: .public)%, charging \(isCharging, privacy: .public)."
        )

        guard Self.isStableBatteryRecalibrationCandidate(pendingReading) else {
            return BatteryTrustResult(
                level: Self.batteryLevel(from: trustedReading.percent),
                historyKindOverride: nil
            )
        }

        acceptBatteryReading(pendingReading.percent, for: mugIdentifier, at: readingTimestamp)
        AppLog.bluetooth.notice(
            "Accepted battery recalibration to \(pendingReading.percent, privacy: .public)% for mug \(mugIdentifier, privacy: .private) after \(pendingReading.sampleCount, privacy: .public) stable samples."
        )
        return BatteryTrustResult(
            level: Self.batteryLevel(from: pendingReading.percent),
            historyKindOverride: .batteryRecalibrated
        )
    }

    private func acceptBatteryReading(_ percent: Int, for mugIdentifier: String, at timestamp: Date) {
        lastTrustedBatteryReadingByMug[mugIdentifier] = TrustedBatteryReading(
            percent: percent,
            timestamp: timestamp
        )
        pendingBatteryReadingByMug.removeValue(forKey: mugIdentifier)
    }

    private func resetBatteryTrust(for mugIdentifier: String?) {
        guard let mugIdentifier else { return }
        lastTrustedBatteryReadingByMug.removeValue(forKey: mugIdentifier)
        pendingBatteryReadingByMug.removeValue(forKey: mugIdentifier)
        lastProcessedBatteryReadingAtByMug.removeValue(forKey: mugIdentifier)
        batteryNotificationStateByMug.removeValue(forKey: mugIdentifier)
    }

    private func updatedPendingBatteryReading(
        for mugIdentifier: String,
        reportedPercent: Int,
        timestamp: Date
    ) -> PendingBatteryReading {
        if
            let pendingReading = pendingBatteryReadingByMug[mugIdentifier],
            abs(reportedPercent - pendingReading.percent) <= Self.batteryRecalibrationStableTolerancePercent
        {
            let updatedReading = PendingBatteryReading(
                percent: reportedPercent,
                firstSeenAt: pendingReading.firstSeenAt,
                latestSeenAt: timestamp,
                sampleCount: pendingReading.sampleCount + 1
            )
            pendingBatteryReadingByMug[mugIdentifier] = updatedReading
            return updatedReading
        }

        let pendingReading = PendingBatteryReading(
            percent: reportedPercent,
            firstSeenAt: timestamp,
            latestSeenAt: timestamp,
            sampleCount: 1
        )
        pendingBatteryReadingByMug[mugIdentifier] = pendingReading
        return pendingReading
    }

    private static func shouldTrustBatteryChange(
        from trustedReading: TrustedBatteryReading,
        to reportedPercent: Int,
        isCharging: Bool,
        timestamp: Date
    ) -> Bool {
        let delta = reportedPercent - trustedReading.percent
        guard abs(delta) > immediateBatteryDeltaPercent else { return true }

        let elapsedMinutes = max(timestamp.timeIntervalSince(trustedReading.timestamp), 0) / 60

        if delta > 0 {
            let allowedIncrease = batteryIncreaseTolerancePercent
                + elapsedMinutes * (isCharging ? chargingBatteryIncreasePercentPerMinute : unpluggedBatteryIncreasePercentPerMinute)
            return Double(delta) <= allowedIncrease
        } else {
            let allowedDrop = batteryDropTolerancePercent
                + elapsedMinutes * (isCharging ? chargingBatteryDropPercentPerMinute : unpluggedBatteryDropPercentPerMinute)
            return Double(abs(delta)) <= allowedDrop
        }
    }

    private static func isStableBatteryRecalibrationCandidate(_ reading: PendingBatteryReading) -> Bool {
        reading.sampleCount >= batteryRecalibrationMinimumSampleCount
            && reading.latestSeenAt.timeIntervalSince(reading.firstSeenAt) >= batteryRecalibrationMinimumDuration
    }

    private func recordHistoryIfNeeded(
        from snapshot: BluetoothRuntimeSnapshot,
        timestamp: Date,
        kindOverride: MugHistoryEventKind?
    ) {
        guard let mugIdentifier = snapshot.activePeripheralIdentifier ?? activePeripheralIdentifier ?? preferredPeripheralIdentifier else {
            return
        }

        recordHistoryIfNeeded(
            mugIdentifier: mugIdentifier,
            isConnected: snapshot.discoveryPhase == .connected,
            batteryLevel: batteryLevel,
            currentTemperatureCelsius: snapshot.currentTemperatureCelsius,
            isHeatingOn: !isTemperatureControlOff,
            timestamp: timestamp,
            kindOverride: kindOverride
        )
    }

    private func recordHistoryIfNeeded(kindOverride: MugHistoryEventKind? = nil) {
        guard let mugIdentifier = activeHistoryMugIdentifier else { return }

        let isConnected = connectionState == .connected
            || (activePeripheralIdentifier != nil && (canWriteTargetTemperature || canReadCurrentTemperature || canReadBattery))

        recordHistoryIfNeeded(
            mugIdentifier: mugIdentifier,
            isConnected: isConnected,
            batteryLevel: batteryLevel,
            currentTemperatureCelsius: currentTemperatureCelsius,
            isHeatingOn: !isTemperatureControlOff,
            timestamp: nowProvider(),
            kindOverride: kindOverride
        )
    }

    private func recordHistoryIfNeeded(
        mugIdentifier: String,
        isConnected: Bool,
        batteryLevel: Double?,
        currentTemperatureCelsius: Double?,
        isHeatingOn: Bool,
        timestamp: Date,
        kindOverride: MugHistoryEventKind?
    ) {
        let state = LoggedMugHistoryState(
            isConnected: isConnected,
            batteryPercent: Self.historyBatteryPercent(from: batteryLevel),
            temperatureCelsius: Self.historyTemperatureCelsius(from: currentTemperatureCelsius),
            isHeatingOn: isHeatingOn
        )

        let previousState = lastLoggedHistoryStateByMug[mugIdentifier]
        guard previousState != state else { return }

        guard
            previousState != nil
                || state.isConnected
                || state.batteryPercent != nil
                || state.temperatureCelsius != nil
        else {
            return
        }

        lastLoggedHistoryStateByMug[mugIdentifier] = state

        let kind: MugHistoryEventKind
        if previousState?.isConnected != state.isConnected {
            kind = state.isConnected ? .connected : .disconnected
        } else if let kindOverride {
            kind = kindOverride
        } else if previousState?.isHeatingOn != state.isHeatingOn {
            kind = .heatingChanged
        } else {
            kind = .reading
        }

        appendMugHistoryEvent(
            MugHistoryEvent(
                timestamp: timestamp,
                mugIdentifier: mugIdentifier,
                appSessionID: appSessionID,
                kind: kind,
                batteryPercent: state.batteryPercent,
                temperatureCelsius: state.temperatureCelsius,
                isHeatingOn: state.isHeatingOn,
                isConnected: state.isConnected
            )
        )
    }

    private func appendMugHistoryEvent(_ event: MugHistoryEvent) {
        guard !mugHistoryEvents.contains(where: { $0.id == event.id }) else { return }

        let eventCountBeforePruning = mugHistoryEvents.count + 1
        let prunedEvents = MugHistoryRetention.pruned(mugHistoryEvents + [event], now: event.timestamp)
        mugHistoryEvents = prunedEvents

        Task { [mugHistoryStore, prunedEvents] in
            try? await mugHistoryStore.append(event)

            if prunedEvents.count < eventCountBeforePruning {
                try? await mugHistoryStore.replaceEvents(prunedEvents)
            }
        }
    }

    private static func historyBatteryPercent(from batteryLevel: Double?) -> Int? {
        guard let batteryLevel else { return nil }
        return batteryPercent(from: batteryLevel)
    }

    private static func historyTemperatureCelsius(from currentTemperatureCelsius: Double?) -> Double? {
        guard let currentTemperatureCelsius else { return nil }
        return (currentTemperatureCelsius * 10).rounded(.toNearestOrAwayFromZero) / 10
    }

    private static func batteryPercent(from batteryLevel: Double?) -> Int? {
        guard let batteryLevel else { return nil }
        return Int((min(max(batteryLevel, 0), 1) * 100).rounded(.toNearestOrAwayFromZero))
    }

    private static func batteryLevel(from percent: Int) -> Double {
        Double(min(max(percent, 0), 100)) / 100
    }

    private static func shouldBreakLegacyBatterySegment(
        previous: (percent: Int, timestamp: Date)?,
        nextPercent: Int?,
        nextTimestamp: Date
    ) -> Bool {
        guard let previous, let nextPercent else { return false }
        guard abs(nextPercent - previous.percent) > legacyBatterySegmentBreakThresholdPercent else {
            return false
        }

        return nextTimestamp.timeIntervalSince(previous.timestamp) <= legacyBatterySegmentBreakWindow
    }

    func handleReconnectOpportunity() {
        synchronizeAutoConnectIdentifiersWithBluetooth()

        if hasConnectedMugSession {
            bluetoothCoordinator?.refreshReadings()
        }

        let hasDisconnectedEligibleMug = reconnectEligibleAutoConnectMugIdentifiers.contains { identifier in
            canStartPreferredScan(for: identifier)
        }
        guard hasDisconnectedEligibleMug else { return }
        bluetoothCoordinator?.recoverAutoConnectMugs()
    }

    private func handleAppResumed() {
        refreshLaunchAtLoginStatus()
        handleReconnectOpportunity()
    }

    private func presentLoginItemApprovalAlertIfNeeded() {
        guard loginItemManager.status == .requiresApproval else { return }

        loginItemAlertTitle = "Approval needed in macOS"
        loginItemAlertMessage = "Allow Swiftea under Login Items in System Settings to launch it when you log in."
        loginItemAlertOffersSystemSettings = true
        isPresentingLoginItemAlert = true
    }

    private func setNotificationPreference(_ preference: NotificationPreference, isEnabled: Bool) {
        guard isEnabled != notificationPreferenceValue(preference) else { return }

        if !isEnabled {
            isPresentingNotificationPermissionAlert = false
            notificationPermissionAlertMessage = ""
            setNotificationPreferenceValue(preference, isEnabled: false)
            return
        }

        requestNotificationAuthorization(for: preference)
    }

    private func notificationPreferenceValue(_ preference: NotificationPreference) -> Bool {
        switch preference {
        case .targetTemperature:
            targetTemperatureNotificationsEnabled
        case .batteryFullyCharged:
            batteryFullyChargedNotificationsEnabled
        case .batteryFullyDischarged:
            batteryFullyDischargedNotificationsEnabled
        }
    }

    private func setNotificationPreferenceValue(_ preference: NotificationPreference, isEnabled: Bool) {
        switch preference {
        case .targetTemperature:
            targetTemperatureNotificationsEnabled = isEnabled
        case .batteryFullyCharged:
            batteryFullyChargedNotificationsEnabled = isEnabled
        case .batteryFullyDischarged:
            batteryFullyDischargedNotificationsEnabled = isEnabled
        }
    }

    private func requestNotificationAuthorization(for preference: NotificationPreference) {
        guard !isRestoringSavedPreferences, !isRequestingNotificationPermission else { return }

        isRequestingNotificationPermission = true
        notificationPermissionAlertMessage = ""
        Task { @MainActor [weak self, targetTemperatureNotifier] in
            let isAuthorized = await targetTemperatureNotifier.requestAuthorizationIfNeeded()
            guard let self else { return }

            self.isRequestingNotificationPermission = false

            if isAuthorized {
                self.setNotificationPreferenceValue(preference, isEnabled: true)
            } else {
                self.preferences.set(false, forKey: preference.preferenceKey)
                self.setNotificationPreferenceValue(preference, isEnabled: false)
                self.notificationPermissionAlertMessage = "macOS is not allowing Swiftea to send notifications. Open System Settings > Notifications and allow notifications for Swiftea, then try again."
                self.isPresentingNotificationPermissionAlert = true
            }
        }
    }

    private func evaluateTargetTemperatureNotification(mugIdentifier: String, isConnected: Bool) {
        guard targetTemperatureNotificationsEnabled else { return }

        guard
            isConnected,
            !isTemperatureControlOff,
            isEmpty != true,
            let currentTemperatureCelsius
        else {
            targetTemperatureNotificationStateByMug[mugIdentifier] = nil
            return
        }

        let targetCelsius = targetTemperatureDraftCelsius
        let targetDisplayValue = Self.targetTemperatureDisplayValue(
            forCelsius: targetCelsius,
            unit: temperatureUnitPreference
        )
        let currentDisplayValue = Self.temperatureDisplayValue(
            celsius: currentTemperatureCelsius,
            unit: temperatureUnitPreference
        )
        .rounded(.toNearestOrAwayFromZero)

        var state = targetTemperatureNotificationStateByMug[mugIdentifier] ?? TargetTemperatureNotificationState()
        if let armedTargetCelsius = state.armedTargetCelsius, abs(armedTargetCelsius - targetCelsius) > 0.05 {
            state.armedTargetCelsius = nil
            state.armedSide = nil
        }
        if let notifiedTargetCelsius = state.notifiedTargetCelsius, abs(notifiedTargetCelsius - targetCelsius) > 0.05 {
            state.notifiedTargetCelsius = nil
        }

        let hasMatchingArmedTarget = state.armedTargetCelsius.map { abs($0 - targetCelsius) <= 0.05 } ?? false
        let hasReachedTarget: Bool = switch state.armedSide {
        case .below:
            hasMatchingArmedTarget && currentDisplayValue >= targetDisplayValue
        case .above:
            hasMatchingArmedTarget && currentDisplayValue <= targetDisplayValue
        case nil:
            false
        }

        if !hasReachedTarget {
            if state.notifiedTargetCelsius == nil {
                if currentDisplayValue < targetDisplayValue {
                    state.armedTargetCelsius = targetCelsius
                    state.armedSide = .below
                } else if currentDisplayValue > targetDisplayValue {
                    state.armedTargetCelsius = targetCelsius
                    state.armedSide = .above
                }
            }
            targetTemperatureNotificationStateByMug[mugIdentifier] = state
            return
        }

        guard
            state.notifiedTargetCelsius == nil
        else {
            targetTemperatureNotificationStateByMug[mugIdentifier] = state
            return
        }

        state.armedTargetCelsius = nil
        state.armedSide = nil
        state.notifiedTargetCelsius = targetCelsius
        targetTemperatureNotificationStateByMug[mugIdentifier] = state

        let mugName = deviceName
        let targetLabel = Self.formatTargetTemperatureValue(targetDisplayValue, unit: temperatureUnitPreference)
        Task { @MainActor [targetTemperatureNotifier] in
            await targetTemperatureNotifier.deliverTargetReachedNotification(
                mugName: mugName,
                targetLabel: targetLabel
            )
        }
    }

    private func evaluateBatteryNotifications(mugIdentifier: String, isConnected: Bool) {
        guard
            isConnected,
            let batteryPercent = Self.batteryPercent(from: batteryLevel)
        else {
            batteryNotificationStateByMug.removeValue(forKey: mugIdentifier)
            return
        }

        var state = batteryNotificationStateByMug[mugIdentifier] ?? BatteryNotificationState()
        let previousPercent = state.lastPercent

        if batteryPercent < 100 {
            state.didNotifyFullyCharged = false
        }
        if batteryPercent > 0 {
            state.didNotifyFullyDischarged = false
        }

        let mugName = deviceName
        if
            batteryFullyChargedNotificationsEnabled,
            previousPercent.map({ $0 < 100 }) == true,
            batteryPercent == 100,
            !state.didNotifyFullyCharged
        {
            state.didNotifyFullyCharged = true
            Task { @MainActor [targetTemperatureNotifier] in
                await targetTemperatureNotifier.deliverBatteryFullyChargedNotification(mugName: mugName)
            }
        }

        if
            batteryFullyDischargedNotificationsEnabled,
            previousPercent.map({ $0 > 0 }) == true,
            batteryPercent == 0,
            !state.didNotifyFullyDischarged
        {
            state.didNotifyFullyDischarged = true
            Task { @MainActor [targetTemperatureNotifier] in
                await targetTemperatureNotifier.deliverBatteryFullyDischargedNotification(mugName: mugName)
            }
        }

        state.lastPercent = batteryPercent
        batteryNotificationStateByMug[mugIdentifier] = state
    }

    private var editingMugHardwareName: String? {
        guard let identifier = mugNameEditingIdentifier ?? activePeripheralIdentifier else {
            return deviceBluetoothName
        }

        if let session = mugSessionsByIdentifier[identifier] {
            return session.deviceBluetoothName ?? session.deviceName
        }

        if identifier == activePeripheralIdentifier || identifier == preferredPeripheralIdentifier {
            return deviceBluetoothName ?? deviceName
        }

        return nil
    }

    private func displayName(for rawName: String, identifier: String?) -> String {
        guard let identifier, let savedName = savedMugNamesByIdentifier[identifier] else {
            return rawName
        }

        return savedName
    }

    private var currentSidebarSubtitle: String {
        switch connectionState {
        case .connected:
            return "Connected now"
        case .connecting:
            return "Connecting"
        case .scanning, .choosing:
            return "Looking for mug"
        case .disconnected, .error:
            return "Ready to reconnect"
        case .permissionNeeded:
            return "Bluetooth permission needed"
        case .bluetoothUnavailable:
            return "Bluetooth unavailable"
        case .starting:
            return "Preparing connection"
        }
    }

    private func savedName(for identifier: String) -> String {
        if let savedName = savedMugNamesByIdentifier[identifier] {
            return savedName
        }

        if identifier == activePeripheralIdentifier || identifier == preferredPeripheralIdentifier {
            return deviceName
        }

        return "Ember Mug 2"
    }

    private func editableMugName(for identifier: String) -> String {
        savedMugNamesByIdentifier[identifier]
            ?? sidebarMugs.first(where: { $0.identifier == identifier })?.name
            ?? savedName(for: identifier)
    }

    private func saveMugName(_ name: String, for identifier: String) {
        let limitedName = Self.limitedMugName(name)
        guard !limitedName.isEmpty else { return }

        addSavedMugIdentifier(identifier)
        savedMugNamesByIdentifier[identifier] = limitedName
        persistSavedMugNames()
        refreshDisplayedNamesFromSavedAliases()
        if identifier == activePeripheralIdentifier {
            preferences.set(deviceName, forKey: AppPreferencesKey.lastKnownDeviceName)
        }
    }

    private func refreshDisplayedNamesFromSavedAliases() {
        if let deviceBluetoothName {
            deviceName = displayName(for: deviceBluetoothName, identifier: activePeripheralIdentifier)
        }

        discoveredMugs = rawDiscoveredMugs.map { mug in
            BluetoothRuntimeSnapshot.DiscoveredMug(
                identifier: mug.identifier,
                name: displayName(for: mug.name, identifier: mug.identifier),
                rssi: mug.rssi,
                finish: mug.finish,
                size: mug.size
            )
        }
    }

    private func persistSavedMugNames() {
        guard !savedMugNamesByIdentifier.isEmpty else {
            preferences.removeValue(forKey: AppPreferencesKey.savedMugNames)
            return
        }

        guard
            let data = try? JSONEncoder().encode(SavedMugNamesPayload(namesByIdentifier: savedMugNamesByIdentifier)),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            return
        }

        preferences.set(jsonString, forKey: AppPreferencesKey.savedMugNames)
    }

    private static func limitedMugName(_ name: String) -> String {
        String(name.prefix(maximumMugNameCharacterCount))
    }

    private static func metadataLabel(finish: EmberMugFinish?, size: EmberMugSize?) -> String? {
        switch (finish?.rawValue, size?.rawValue) {
        case let (finish?, size?):
            return "\(finish) • \(size)"
        case let (finish?, nil):
            return finish
        case let (nil, size?):
            return size
        case (nil, nil):
            return nil
        }
    }
}
