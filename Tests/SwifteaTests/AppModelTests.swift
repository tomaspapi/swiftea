import AppKit
import Foundation
import Testing
@testable import Swiftea

@MainActor
struct AppModelTests {
    @Test func launchAtLoginUsesTheSystemLoginItemAsItsSourceOfTruth() {
        let loginItemManager = RecordingLoginItemManager(status: .enabled)
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            loginItemManager: loginItemManager
        )

        #expect(model.launchesAtLogin)

        model.setLaunchesAtLogin(false)

        #expect(loginItemManager.requestedValues == [false])
        #expect(!model.launchesAtLogin)

        model.setLaunchesAtLogin(true)

        #expect(loginItemManager.requestedValues == [false, true])
        #expect(model.launchesAtLogin)
    }

    @Test func menuBarStatusShowsTemperatureOnlyForFilledConnectedMug() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        #expect(model.menuBarStatusTemperatureLabel == nil)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: false, currentTemperatureCelsius: 54))

        #expect(model.menuBarStatusTemperatureLabel == "54°C")
        #expect(model.menuBarCurrentTemperatureLine == "Current temperature: 54°C")
        #expect(model.menuBarTargetTemperatureLine == "Target temperature: 57°C")
        #expect(model.menuBarBatteryLine == "70% Battery")

        model.temperatureUnitPreference = .fahrenheit

        #expect(model.menuBarStatusTemperatureLabel == AppModel.format(celsius: 54, unit: .fahrenheit))
        #expect(model.menuBarCurrentTemperatureLine == "Current temperature: \(AppModel.format(celsius: 54, unit: .fahrenheit))")

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: true, currentTemperatureCelsius: 54))

        #expect(model.menuBarStatusTemperatureLabel == nil)
        #expect(model.menuBarCurrentTemperatureLine == "Empty")
        #expect(model.menuBarTargetTemperatureLine == "Heating off")

        let chargingModel = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        chargingModel.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: false, currentTemperatureCelsius: 54, batteryLevel: 0.87, isCharging: true))

        #expect(chargingModel.menuBarBatteryLine == "Charging: 87%")
    }

    @Test func targetTemperatureDraftIsClampedToSupportedRange() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.setTargetTemperatureDraft(to: 90)

        #expect(model.targetTemperatureDraftCelsius == 62)
    }

    @Test func targetTemperatureDraftUsesWholeCelsiusValues() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.setTargetTemperatureDraft(to: 61.4)

        #expect(model.targetTemperatureDraftCelsius == 61)

        model.setTargetTemperatureDraft(to: 61.9)

        #expect(model.targetTemperatureDraftCelsius == 62)
    }

    @Test func choosingPresetUpdatesTargetTemperature() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        let preset = model.presets[2]

        model.choosePreset(preset)

        #expect(model.targetTemperatureDraftCelsius == preset.celsius)
    }

    @Test func zeroTargetSnapshotKeepsDraftButMarksHeatingOff() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.setTargetTemperatureDraft(to: 60)

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-1",
                discoveredDeviceName: "Desk Mug",
                discoveredDeviceFinish: .black,
                discoveredDeviceSize: .ounce10,
                serialNumber: nil,
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "Connected.",
                currentTemperatureCelsius: 54,
                targetTemperatureCelsius: 0,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: nil,
                canReadCurrentTemperature: true,
                canReadTargetTemperature: true,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: true,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 60)
        #expect(model.targetTemperatureLabel == "Off")
    }

    @Test func turningHeatingBackOnUsesRememberedDraft() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.connectionState = .connected
        model.canWriteTargetTemperature = true
        model.isTemperatureControlOff = true
        model.setTargetTemperatureDraft(to: 58)

        model.setTemperatureControlEnabled(true)

        #expect(!model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 58)
        #expect(model.targetTemperatureLabel == AppModel.format(celsius: 58))
    }

    @Test func emptyMugHeatingConfirmationStaysOnRequestingSurface() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 0,
                isEmpty: true
            )
        )

        model.setTemperatureControlEnabled(
            true,
            emptyMugAlertPresentation: .menuBar
        )

        #expect(model.emptyHeatingAlertPresentation == .menuBar)
        #expect(model.isTemperatureControlOff)

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 0,
                isEmpty: true
            )
        )

        #expect(model.emptyHeatingAlertPresentation == .menuBar)
        #expect(model.isTemperatureControlOff)

        model.confirmEmptyHeatingAlert()

        #expect(model.emptyHeatingAlertPresentation == nil)
        #expect(!model.isTemperatureControlOff)
    }

    @Test func heatingToggleSoundFollowsHumanToggleChangesImmediately() {
        let soundPlayer = SpyHeatingToggleSoundPlayer()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            heatingToggleSoundPlayer: soundPlayer
        )
        model.connectionState = .connected
        model.canWriteTargetTemperature = true
        model.isTemperatureControlOff = true

        model.setTemperatureControlEnabled(true)
        model.setTemperatureControlEnabled(false)

        #expect(soundPlayer.events == [true, false])
    }

    @Test func heatingToggleSoundFollowsAutomaticEmptyAndFullTransitions() {
        let soundPlayer = SpyHeatingToggleSoundPlayer()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            heatingToggleSoundPlayer: soundPlayer
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: false))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: true))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: false))

        #expect(soundPlayer.events == [true, false, true])
    }

    @Test func heatingToggleSoundsCanBeDisabledAndPreferencePersists() {
        let preferences = InMemoryAppPreferencesStore()
        let soundPlayer = SpyHeatingToggleSoundPlayer()
        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            heatingToggleSoundPlayer: soundPlayer
        )
        model.connectionState = .connected
        model.canWriteTargetTemperature = true
        model.isTemperatureControlOff = true

        model.setSoundsEnabled(false)
        model.setTemperatureControlEnabled(true)
        model.setTemperatureControlEnabled(false)

        #expect(!model.soundsEnabled)
        #expect(preferences.bool(forKey: AppPreferencesKey.soundsEnabled) == false)
        #expect(soundPlayer.events.isEmpty)

        let restoredModel = AppModel(startBluetooth: false, preferences: preferences)
        #expect(!restoredModel.soundsEnabled)
    }

    @Test func emptyMugTurnsVisibleHeatingOffWithoutClearingFirmwareTarget() {
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            bluetoothCoordinator: bluetoothCoordinator
        )

        model.setTargetTemperatureDraft(to: 58)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: false))
        bluetoothCoordinator.targetWrites.removeAll()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: true))

        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 58)
        #expect(bluetoothCoordinator.targetWrites.isEmpty)
    }

    @Test func emptyMugWithZeroTargetRearmsStandaloneHeatingWithRememberedDraft() {
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            bluetoothCoordinator: bluetoothCoordinator
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: false))
        model.setTargetTemperatureDraft(to: 56)
        model.turnTemperatureControlOff()
        #expect(bluetoothCoordinator.targetWrites.last == .init(celsius: nil, identifier: "MUG-1"))

        bluetoothCoordinator.targetWrites.removeAll()
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: true))

        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 56)
        #expect(bluetoothCoordinator.targetWrites == [.init(celsius: 56, identifier: "MUG-1")])
    }

    @Test func emptyMugWithArmedTargetKeepsToggleOffWhileRememberingTarget() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: true))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 56, isEmpty: true))

        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 56)
        #expect(model.targetTemperatureLabel == "Off")
    }

    @Test func initialEmptyConnectionDoesNotClearFirmwareTarget() {
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            bluetoothCoordinator: bluetoothCoordinator
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: true))

        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 58)
        #expect(bluetoothCoordinator.targetWrites.isEmpty)
    }

    @Test func refilledMugAutomaticallyResumesHeatingWithRememberedDraft() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: false))
        model.setTargetTemperatureDraft(to: 56, reenableIfNeeded: true)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: true))
        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 56)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: false))

        #expect(!model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 56)
        #expect(model.targetTemperatureLabel == AppModel.format(celsius: 56))
    }

    @Test func firstNonEmptySnapshotTurnsHeatingOnAfterInitialSafetyOff() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.setTargetTemperatureDraft(to: 56)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, isEmpty: false))

        #expect(!model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 56)
    }

    @Test func firstEmptySnapshotKeepsHeatingOffAfterInitialSafetyOff() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.setTargetTemperatureDraft(to: 56)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, isEmpty: true))

        #expect(model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 56)
        #expect(model.targetTemperatureLabel == "Off")
    }

    @Test func batteryFillFractionTracksExactBatteryPercentage() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.batteryLevel = 0.52
        #expect(model.batteryFillFraction == 0.52)

        model.batteryLevel = 1.3
        #expect(model.batteryFillFraction == 1)

        model.batteryLevel = -0.2
        #expect(model.batteryFillFraction == 0)
    }

    @Test func impossibleBatterySpikeIsHeldOutOfUIAndHistory() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                batteryLevel: 0.76,
                isCharging: false
            )
        )
        #expect(abs((model.batteryLevel ?? 0) - 0.76) < 0.0001)

        now = now.addingTimeInterval(29)
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                batteryLevel: 1,
                isCharging: true
            )
        )

        #expect(abs((model.batteryLevel ?? 0) - 0.76) < 0.0001)
        #expect(model.isCharging)
        #expect(!historyEvents(for: "MUG-1", in: model).contains { $0.batteryPercent == 100 })
    }

    @Test func suspiciousStableBatteryValueIsAcceptedAsRecalibrationWithChartGap() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                batteryLevel: 0.76,
                isCharging: false
            )
        )

        now = now.addingTimeInterval(29)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, batteryLevel: 1, isCharging: true))
        now = now.addingTimeInterval(30)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, batteryLevel: 1, isCharging: true))
        now = now.addingTimeInterval(65)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, batteryLevel: 0.99, isCharging: true))

        let events = historyEvents(for: "MUG-1", in: model)
        let batterySegments = model.historyChartSegments(metric: .battery, now: now)

        #expect(abs((model.batteryLevel ?? 0) - 0.99) < 0.0001)
        #expect(events.last?.kind == .batteryRecalibrated)
        #expect(events.last?.batteryPercent == 99)
        #expect(batterySegments.count == 2)
    }

    @Test func plausibleBatteryIncreaseIsAcceptedImmediately() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, batteryLevel: 0.76, isCharging: true))
        now = now.addingTimeInterval(120)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, batteryLevel: 0.79, isCharging: true))

        #expect(abs((model.batteryLevel ?? 0) - 0.79) < 0.0001)
        #expect(historyEvents(for: "MUG-1", in: model).last?.batteryPercent == 79)
    }

    @Test func deniedBluetoothAccessBecomesPermissionState() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .denied,
                hardwareState: .poweredOn,
                discoveryPhase: .idle,
                activePeripheralIdentifier: nil,
                discoveredDeviceName: nil,
                discoveredDeviceFinish: nil,
                discoveredDeviceSize: nil,
                serialNumber: nil,
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "No access.",
                currentTemperatureCelsius: nil,
                targetTemperatureCelsius: nil,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: nil,
                canReadCurrentTemperature: false,
                canReadTargetTemperature: false,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: false,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.connectionState == .permissionNeeded)
        #expect(model.connectionActionTitle == "Open Bluetooth Settings")
    }

    @Test func connectedSnapshotPromotesConnectedStateAndDeviceName() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        let rememberedTarget = model.targetTemperatureDraftCelsius

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-1",
                discoveredDeviceName: "Desk Ember Mug 2",
                discoveredDeviceFinish: .black,
                discoveredDeviceSize: .ounce10,
                serialNumber: "PBBG14105067",
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "Connected.",
                currentTemperatureCelsius: 55.0,
                targetTemperatureCelsius: 58.0,
                batteryLevel: 0.7,
                isCharging: true,
                contentsLevelRaw: 30,
                liquidStateDescription: "Holding temperature",
                isEmpty: false,
                canReadCurrentTemperature: true,
                canReadTargetTemperature: true,
                canReadBattery: true,
                canReadContents: true,
                canReadActivity: true,
                canWriteTargetTemperature: true,
                lastConnectedAt: Date(timeIntervalSince1970: 1_713_657_600),
                lastReadingAt: Date(timeIntervalSince1970: 1_713_657_720),
                lastTargetWriteAt: Date(timeIntervalSince1970: 1_713_657_780)
            )
        )

        #expect(model.connectionState == .connected)
        #expect(model.deviceName == "Desk Ember Mug 2")
        #expect(model.deviceFinish == .black)
        #expect(model.deviceSize == .ounce10)
        #expect(model.deviceSerialNumber == "PBBG14105067")
        #expect(model.bluetoothIdentifierLabel == "MUG-1")
        #expect(model.currentTemperatureCelsius == 55.0)
        #expect(!model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == rememberedTarget)
        #expect(model.canAdjustTemperature)
        #expect(model.canRefreshReadings)
        #expect(model.currentTemperaturePathLabel == "Ready and updating")
        #expect(model.targetTemperaturePathLabel == "Read and write ready")
        #expect(model.batteryPathLabel == "Ready and updating")
        #expect(model.contentsPathLabel == "Ready and updating")
        #expect(model.contentsStatusLabel == "Has liquid")
    }

    @Test func initialFullSnapshotUsesRememberedTargetInsteadOfMugReadBack() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.setTargetTemperatureDraft(to: 56)

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-1",
                discoveredDeviceName: "Ember Mug 2",
                discoveredDeviceFinish: nil,
                discoveredDeviceSize: nil,
                serialNumber: nil,
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "Connected.",
                currentTemperatureCelsius: nil,
                targetTemperatureCelsius: 62.5,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: false,
                canReadCurrentTemperature: false,
                canReadTargetTemperature: true,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: true,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.targetTemperatureDraftCelsius == 56)
        #expect(model.targetTemperatureLabel == "56°C")
    }

    @Test func staleTargetReadBackAfterOptimisticWindowDoesNotOverrideLocalTemperatureChoice() async throws {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.setTargetTemperatureDraft(to: 55)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55))
        #expect(model.targetTemperatureDraftCelsius == 55)

        model.setTargetTemperatureDraft(to: 50, reenableIfNeeded: true)

        try await Task.sleep(nanoseconds: 2_700_000_000)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, detailMessage: "Late stale target read."))

        #expect(!model.isTemperatureControlOff)
        #expect(model.connectionState == .connected)
        #expect(model.targetTemperatureDraftCelsius == 50)
        #expect(model.targetTemperatureLabel == "50°C")
    }

    @Test func reconnectKeepsRememberedTargetAfterLocalTemperatureChoice() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.setTargetTemperatureDraft(to: 55)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55))
        model.setTargetTemperatureDraft(to: 50, reenableIfNeeded: true)

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: nil,
                discoveryPhase: .disconnected,
                detailMessage: "Disconnected.",
                canWriteTargetTemperature: false
            )
        )
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 57))

        #expect(model.connectionState == .connected)
        #expect(!model.isTemperatureControlOff)
        #expect(model.targetTemperatureDraftCelsius == 50)
        #expect(model.targetTemperatureLabel == "50°C")
    }

    @Test func connectedSnapshotWithoutReadBackShowsWriteOnlyTargetPath() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-1",
                discoveredDeviceName: "Ember Mug 2",
                discoveredDeviceFinish: nil,
                discoveredDeviceSize: nil,
                serialNumber: nil,
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "Connected, but still confirming characteristics.",
                currentTemperatureCelsius: nil,
                targetTemperatureCelsius: nil,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: nil,
                canReadCurrentTemperature: false,
                canReadTargetTemperature: false,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: true,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.connectionState == .connected)
        #expect(model.targetTemperaturePathLabel == "Write ready")
        #expect(model.temperatureControlHint == "Heating is off. Turn it back on or choose a preset to start heating again.")
        #expect(model.connectedSidebarMugs.isEmpty)
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-1"])
        #expect(!model.shouldShowMugDashboard)
        #expect(!model.canEditCurrentMugName)
    }

    @Test func savedTargetTemperatureDraftIsRestoredOnInit() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(62.5, forKey: AppPreferencesKey.targetTemperatureDraftCelsius)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.targetTemperatureDraftCelsius == 62)
    }

    @Test func savedThemeTemperatureUnitAndTimeFormatPreferencesAreRestoredOnInit() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("dark", forKey: AppPreferencesKey.themePreference)
        preferences.set("fahrenheit", forKey: AppPreferencesKey.temperatureUnitPreference)
        preferences.set("twelveHour", forKey: AppPreferencesKey.timeFormatPreference)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.themePreference == .dark)
        #expect(model.temperatureUnitPreference == .fahrenheit)
        #expect(model.timeFormatPreference == .twelveHour)
    }

    @Test func missingDisplayPreferencesCanDefaultFromSystemSettingsWithoutPersistingImmediately() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            systemPreferenceDefaults: .init(
                temperatureUnitPreference: .fahrenheit,
                timeFormatPreference: .twelveHour
            )
        )

        #expect(model.temperatureUnitPreference == .fahrenheit)
        #expect(model.timeFormatPreference == .twelveHour)
        #expect(preferences.string(forKey: AppPreferencesKey.temperatureUnitPreference) == nil)
        #expect(preferences.string(forKey: AppPreferencesKey.timeFormatPreference) == nil)
    }

    @Test func savedChartTimeframePreferenceIsRestoredOnInit() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("twelveHours", forKey: AppPreferencesKey.chartTimeframePreference)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.chartTimeframePreference == .twelveHours)
    }

    @Test func keepRunningWhenWindowClosedPreferenceIsRestoredOnInit() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(false, forKey: AppPreferencesKey.keepsRunningWhenWindowClosed)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(!model.keepsRunningWhenWindowClosed)
    }

    @Test func appLocationPreferenceIsRestoredOnInit() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("menuBar", forKey: AppPreferencesKey.appLocationPreference)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.appLocationPreference == .menuBar)
    }

    @Test func onboardingPresentsOnceOnBrandNewInstallUntilCompleted() {
        let preferences = InMemoryAppPreferencesStore()
        let acceptanceDate = Date(timeIntervalSince1970: 1_750_000_000)
        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            nowProvider: { acceptanceDate }
        )

        #expect(model.shouldPresentOnboarding)
        #expect(!model.shouldStartOnboardingAtLegalAgreement)
        #expect(!model.hasAcceptedCurrentTermsOfUse)
        #expect(!model.hasAcceptedCurrentSafetyNotice)
        #expect(!model.hasAcceptedCurrentLegalDocuments)
        #expect(model.consumeOnboardingPresentation())
        #expect(!model.consumeOnboardingPresentation())

        model.acceptCurrentLegalDocumentsAndCompleteOnboarding()

        #expect(!model.shouldPresentOnboarding)
        #expect(model.hasAcceptedCurrentTermsOfUse)
        #expect(model.hasAcceptedCurrentSafetyNotice)
        #expect(model.hasAcceptedCurrentLegalDocuments)
        #expect(preferences.bool(forKey: AppPreferencesKey.hasCompletedOnboarding) == true)
        #expect(
            preferences.string(forKey: AppPreferencesKey.acceptedTermsVersion)
                == SwifteaLegalDocuments.currentTermsVersion
        )
        #expect(
            preferences.string(forKey: AppPreferencesKey.acceptedTermsDate)
                == ISO8601DateFormatter().string(from: acceptanceDate)
        )
        #expect(
            preferences.string(forKey: AppPreferencesKey.acceptedSafetyNoticeVersion)
                == SwifteaLegalDocuments.currentSafetyNoticeVersion
        )
        #expect(
            preferences.string(forKey: AppPreferencesKey.acceptedSafetyNoticeDate)
                == ISO8601DateFormatter().string(from: acceptanceDate)
        )

        let restoredModel = AppModel(startBluetooth: false, preferences: preferences)
        #expect(!restoredModel.shouldPresentOnboarding)
    }

    @Test func legalTermsPreserveMandatoryLawWithoutCatalogingRemedies() throws {
        let agreement = try #require(
            SwifteaLegalDocuments.termsOfUse.sections.first {
                $0.title == "1. Agreement"
            }
        )
        let release = try #require(
            SwifteaLegalDocuments.termsOfUse.sections.first {
                $0.title == "12. Assumption of risk and release"
            }
        )
        let liability = try #require(
            SwifteaLegalDocuments.termsOfUse.sections.first {
                $0.title == "13. Limitation of liability"
            }
        )
        let localRights = try #require(
            SwifteaLegalDocuments.termsOfUse.sections.first {
                $0.title == "16. Rights that cannot be waived"
            }
        )
        let governingLaw = try #require(
            SwifteaLegalDocuments.termsOfUse.sections.first {
                $0.title == "17. Governing law and general terms"
            }
        )

        #expect(agreement.body.contains("Sections 5–7 and 11–13 are especially important"))
        #expect(agreement.body.contains("release of certain claims"))
        #expect(release.body.contains("incorrect or unintended commands"))
        #expect(release.body.contains("ordinary negligence"))
        #expect(release.body.contains("gross negligence"))
        #expect(release.body.contains("gross fault"))
        #expect(release.body.contains("intentional misconduct"))
        #expect(liability.body.contains("tort (including ordinary negligence)"))
        #expect(liability.body.contains("gross negligence"))
        #expect(liability.body.contains("gross fault"))
        #expect(liability.body.contains("intentional misconduct"))
        #expect(localRights.body.contains("right, remedy, guarantee, warranty, or liability"))
        #expect(localRights.body.contains("only to the extent of the conflict"))
        #expect(!localRights.body.contains("regulator or law-enforcement authority"))
        #expect(!localRights.body.contains("class or collective proceeding"))
        #expect(governingLaw.body.contains("where legally permitted"))
        #expect(governingLaw.body.contains("to the extent permitted by applicable law"))
    }

    @Test func existingInstallPresentsOnlyTheLegalAgreementUntilAccepted() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("dark", forKey: AppPreferencesKey.themePreference)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.shouldPresentOnboarding)
        #expect(model.shouldStartOnboardingAtLegalAgreement)

        model.acceptCurrentLegalDocumentsAndCompleteOnboarding()

        let restoredModel = AppModel(startBluetooth: false, preferences: preferences)
        #expect(!restoredModel.shouldPresentOnboarding)
        #expect(!restoredModel.shouldStartOnboardingAtLegalAgreement)
    }

    @Test func outdatedLegalTermsRequireAcceptanceAgain() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(true, forKey: AppPreferencesKey.hasCompletedOnboarding)
        preferences.set("2025-01-01", forKey: AppPreferencesKey.acceptedTermsVersion)
        preferences.set(
            SwifteaLegalDocuments.currentSafetyNoticeVersion,
            forKey: AppPreferencesKey.acceptedSafetyNoticeVersion
        )

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.shouldPresentOnboarding)
        #expect(model.shouldStartOnboardingAtLegalAgreement)
        #expect(!model.hasAcceptedCurrentTermsOfUse)
        #expect(model.hasAcceptedCurrentSafetyNotice)
        #expect(!model.hasAcceptedCurrentLegalDocuments)
    }

    @Test func outdatedSafetyNoticeRequiresAcceptanceAgain() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(true, forKey: AppPreferencesKey.hasCompletedOnboarding)
        preferences.set(
            SwifteaLegalDocuments.currentTermsVersion,
            forKey: AppPreferencesKey.acceptedTermsVersion
        )
        preferences.set("0.9", forKey: AppPreferencesKey.acceptedSafetyNoticeVersion)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.shouldPresentOnboarding)
        #expect(model.shouldStartOnboardingAtLegalAgreement)
        #expect(model.hasAcceptedCurrentTermsOfUse)
        #expect(!model.hasAcceptedCurrentSafetyNotice)
        #expect(!model.hasAcceptedCurrentLegalDocuments)
    }

    @Test func bluetoothRuntimeStaysDormantUntilBothCurrentLegalDocumentsAreAccepted() {
        let preferences = InMemoryAppPreferencesStore()
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let model = AppModel(
            startBluetooth: true,
            preferences: preferences,
            heatingToggleSoundPlayer: SilentHeatingToggleSoundPlayer.shared,
            targetTemperatureNotifier: SilentTargetTemperatureNotificationCenter.shared,
            idleSleepPreventionManager: NoOpIdleSleepPreventionManager.shared,
            mugHistoryStore: InMemoryMugHistoryStore(),
            bluetoothCoordinator: bluetoothCoordinator,
            systemPreferenceDefaults: .stableTesting
        )

        model.handleReconnectOpportunity()

        #expect(bluetoothCoordinator.preferredIdentifierUpdates.isEmpty)
        #expect(bluetoothCoordinator.autoConnectIdentifierUpdates.isEmpty)
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 0)

        model.acceptCurrentLegalDocumentsAndCompleteOnboarding()

        #expect(bluetoothCoordinator.preferredIdentifierUpdates == [nil])
        #expect(bluetoothCoordinator.autoConnectIdentifierUpdates == [[]])
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 1)

        model.acceptCurrentLegalDocumentsAndCompleteOnboarding()
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 1)
    }

    @Test func bluetoothRuntimeStartsImmediatelyWhenBothAcceptedVersionsAreCurrent() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            SwifteaLegalDocuments.currentTermsVersion,
            forKey: AppPreferencesKey.acceptedTermsVersion
        )
        preferences.set(
            SwifteaLegalDocuments.currentSafetyNoticeVersion,
            forKey: AppPreferencesKey.acceptedSafetyNoticeVersion
        )
        let bluetoothCoordinator = RecordingBluetoothCoordinator()

        _ = AppModel(
            startBluetooth: true,
            preferences: preferences,
            heatingToggleSoundPlayer: SilentHeatingToggleSoundPlayer.shared,
            targetTemperatureNotifier: SilentTargetTemperatureNotificationCenter.shared,
            idleSleepPreventionManager: NoOpIdleSleepPreventionManager.shared,
            mugHistoryStore: InMemoryMugHistoryStore(),
            bluetoothCoordinator: bluetoothCoordinator,
            systemPreferenceDefaults: .stableTesting
        )

        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 1)
    }

    @Test func updateChangelogDoesNotPresentOnFirstInstallAndRecordsCurrentVersion() {
        let preferences = InMemoryAppPreferencesStore()

        let model = AppModel(startBluetooth: false, preferences: preferences, appVersionIdentifier: "1.0.0 (10)")

        #expect(!model.shouldPresentUpdateChangelog)
        #expect(preferences.string(forKey: AppPreferencesKey.lastPresentedChangelogVersion) == "1.0.0 (10)")
    }

    @Test func updateChangelogPresentsOnceAfterVersionChange() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("1.0.0 (10)", forKey: AppPreferencesKey.lastPresentedChangelogVersion)

        let model = AppModel(startBluetooth: false, preferences: preferences, appVersionIdentifier: "1.1.0 (11)")

        #expect(model.shouldPresentUpdateChangelog)
        #expect(model.consumeUpdateChangelogPresentation())
        #expect(!model.shouldPresentUpdateChangelog)
        #expect(preferences.string(forKey: AppPreferencesKey.lastPresentedChangelogVersion) == "1.1.0 (11)")
        #expect(!model.consumeUpdateChangelogPresentation())
    }

    @Test func updateChangelogCollectsEveryMissedPublishedVersion() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("1.0.0 (10)", forKey: AppPreferencesKey.lastPresentedChangelogVersion)
        let changelog = """
        # Changelog

        ## Unreleased

        - Still in development.

        ## 1.3.0

        - Third release.

        ## 1.2.0

        - Second release.

        ## 1.1.0

        - First release.

        ## 1.0.0

        - Initial release.
        """

        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            appVersionIdentifier: "1.3.0 (13)",
            changelogMarkdown: changelog
        )

        #expect(model.updateChangelogReleases.map(\.version) == ["1.3.0", "1.2.0", "1.1.0"])
        #expect(model.updateChangelogReleases.map(\.notes) == [
            ["Third release."],
            ["Second release."],
            ["First release."]
        ])
    }

    @Test func updateChangelogPresentsForExistingInstallWithoutTrackerKey() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("dark", forKey: AppPreferencesKey.themePreference)

        let model = AppModel(startBluetooth: false, preferences: preferences, appVersionIdentifier: "1.1.0 (11)")

        #expect(model.shouldPresentUpdateChangelog)
        #expect(preferences.string(forKey: AppPreferencesKey.lastPresentedChangelogVersion) == nil)
    }

    @Test func publishedChangelogUsesCurrentVersionSection() {
        let changelog = """
        # Changelog

        ## Unreleased

        - Internal draft.

        ## 1.1.0

        - Added the good stuff.
        - Kept the app tidy.

        ## 1.0.0

        - Initial release.
        """

        let notes = PublishedChangelog.releaseNotesMarkdown(from: changelog, version: "1.1.0")

        #expect(notes == "- Added the good stuff.\n- Kept the app tidy.")
    }

    @Test func targetTemperatureNotificationPreferencePersistsAndRequestsAuthorization() async {
        let preferences = InMemoryAppPreferencesStore()
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: preferences, targetTemperatureNotifier: notifier)

        model.setTargetTemperatureNotificationsEnabled(true)
        await Task.yield()

        #expect(model.targetTemperatureNotificationsEnabled)
        #expect(preferences.bool(forKey: AppPreferencesKey.targetTemperatureNotificationsEnabled) == true)
        #expect(notifier.authorizationRequestCount == 1)
    }

    @Test func deniedNotificationAuthorizationTurnsSettingBackOff() async {
        let preferences = InMemoryAppPreferencesStore()
        let notifier = RecordingTargetTemperatureNotifier()
        notifier.authorizationResult = false
        let model = AppModel(startBluetooth: false, preferences: preferences, targetTemperatureNotifier: notifier)

        model.setTargetTemperatureNotificationsEnabled(true)
        await Task.yield()
        await Task.yield()

        #expect(!model.targetTemperatureNotificationsEnabled)
        #expect(preferences.bool(forKey: AppPreferencesKey.targetTemperatureNotificationsEnabled) == false)
        #expect(model.isPresentingNotificationPermissionAlert)
        #expect(model.notificationPermissionAlertMessage.contains("System Settings"))
    }

    @Test func batteryNotificationPreferencesPersistAndRequestAuthorization() async {
        let preferences = InMemoryAppPreferencesStore()
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: preferences, targetTemperatureNotifier: notifier)

        model.setBatteryFullyDischargedNotificationsEnabled(true)
        await Task.yield()
        model.setBatteryFullyChargedNotificationsEnabled(true)
        await Task.yield()

        #expect(model.batteryFullyDischargedNotificationsEnabled)
        #expect(model.batteryFullyChargedNotificationsEnabled)
        #expect(preferences.bool(forKey: AppPreferencesKey.batteryFullyDischargedNotificationsEnabled) == true)
        #expect(preferences.bool(forKey: AppPreferencesKey.batteryFullyChargedNotificationsEnabled) == true)
        #expect(notifier.authorizationRequestCount == 2)
    }

    @Test func restoredNotificationPreferencesDoNotRequestAuthorization() async {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(true, forKey: AppPreferencesKey.targetTemperatureNotificationsEnabled)
        preferences.set(true, forKey: AppPreferencesKey.batteryFullyChargedNotificationsEnabled)
        preferences.set(true, forKey: AppPreferencesKey.batteryFullyDischargedNotificationsEnabled)
        let notifier = RecordingTargetTemperatureNotifier()

        let model = AppModel(startBluetooth: false, preferences: preferences, targetTemperatureNotifier: notifier)
        await Task.yield()

        #expect(model.targetTemperatureNotificationsEnabled)
        #expect(model.batteryFullyChargedNotificationsEnabled)
        #expect(model.batteryFullyDischargedNotificationsEnabled)
        #expect(notifier.authorizationRequestCount == 0)
    }

    @Test func fahrenheitPreferenceFormatsDisplayedTemperatures() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)
        model.currentTemperatureCelsius = 50
        model.isTemperatureControlOff = false
        model.setTargetTemperatureDraft(to: 57)

        model.temperatureUnitPreference = .fahrenheit

        #expect(model.currentTemperatureLabel == AppModel.format(celsius: 50, unit: .fahrenheit))
        #expect(model.targetTemperatureLabel == "135°F")
        #expect(preferences.string(forKey: AppPreferencesKey.temperatureUnitPreference) == "fahrenheit")
    }

    @Test func targetTemperatureNotificationFiresWhenMugReachesSelectedTarget() async {
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), targetTemperatureNotifier: notifier)
        model.setTargetTemperatureDraft(to: 55)
        model.setTargetTemperatureNotificationsEnabled(true)
        await Task.yield()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, currentTemperatureCelsius: 54))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, currentTemperatureCelsius: 55))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, currentTemperatureCelsius: 55.2))
        await Task.yield()

        #expect(notifier.deliveries == [
            .init(mugName: "Ember Mug 2", targetLabel: "55°C")
        ])
    }

    @Test func targetTemperatureNotificationFiresWhenMugCoolsDownToSelectedTarget() async {
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), targetTemperatureNotifier: notifier)
        model.setTargetTemperatureDraft(to: 55)
        model.setTargetTemperatureNotificationsEnabled(true)
        await Task.yield()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, currentTemperatureCelsius: 56))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, currentTemperatureCelsius: 55))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, currentTemperatureCelsius: 54.8))
        await Task.yield()

        #expect(notifier.deliveries == [
            .init(mugName: "Ember Mug 2", targetLabel: "55°C")
        ])
    }

    @Test func targetTemperatureNotificationUsesFahrenheitPreference() async {
        let notifier = RecordingTargetTemperatureNotifier()
        let targetCelsius = (137.0 - 32.0) * 5.0 / 9.0
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("fahrenheit", forKey: AppPreferencesKey.temperatureUnitPreference)
        preferences.set(targetCelsius, forKey: AppPreferencesKey.targetTemperatureDraftCelsius)
        let model = AppModel(startBluetooth: false, preferences: preferences, targetTemperatureNotifier: notifier)
        model.setTargetTemperatureNotificationsEnabled(true)
        await Task.yield()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: targetCelsius, currentTemperatureCelsius: targetCelsius - 1))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: targetCelsius, currentTemperatureCelsius: targetCelsius))
        await Task.yield()

        #expect(notifier.deliveries == [
            .init(mugName: "Ember Mug 2", targetLabel: "137°F")
        ])
    }

    @Test func batteryFullyChargedNotificationFiresOnceWhenTrustedBatteryReaches100() async {
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), targetTemperatureNotifier: notifier)
        model.setBatteryFullyChargedNotificationsEnabled(true)
        await Task.yield()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 0.99, isCharging: true))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 1, isCharging: true))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 1, isCharging: true))
        await Task.yield()

        #expect(notifier.batteryEvents == [
            .fullyCharged(mugName: "Ember Mug 2")
        ])
    }

    @Test func batteryFullyDischargedNotificationFiresOnceWhenTrustedBatteryReaches0() async {
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), targetTemperatureNotifier: notifier)
        model.setBatteryFullyDischargedNotificationsEnabled(true)
        await Task.yield()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 0.01))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 0))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 0))
        await Task.yield()

        #expect(notifier.batteryEvents == [
            .fullyDischarged(mugName: "Ember Mug 2")
        ])
    }

    @Test func batteryEndpointNotificationsDoNotFireOnFirstReading() async {
        let notifier = RecordingTargetTemperatureNotifier()
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), targetTemperatureNotifier: notifier)
        model.setBatteryFullyChargedNotificationsEnabled(true)
        await Task.yield()
        model.setBatteryFullyDischargedNotificationsEnabled(true)
        await Task.yield()

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, batteryLevel: 1, isCharging: true))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 55, activePeripheralIdentifier: "MUG-2", batteryLevel: 0))
        await Task.yield()

        #expect(notifier.batteryEvents.isEmpty)
    }

    @Test func fahrenheitTargetControlStepsByOneDisplayedDegree() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.isTemperatureControlOff = false
        model.setTargetTemperatureDraft(to: 55)
        model.temperatureUnitPreference = .fahrenheit

        #expect(model.targetTemperatureLabel == "131°F")

        model.increaseTemperatureDraft()

        #expect(model.targetTemperatureLabel == "132°F")
        #expect(abs(model.targetTemperatureDraftCelsius - (100.0 * 5.0 / 9.0)) < 0.0001)

        model.decreaseTemperatureDraft()

        #expect(model.targetTemperatureLabel == "131°F")
        #expect(abs(model.targetTemperatureDraftCelsius - 55) < 0.0001)
    }

    @Test func fahrenheitTargetControlStopsAtAppOfferedMaximum() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())
        model.isTemperatureControlOff = false
        model.setTargetTemperatureDraft(to: 62)
        model.temperatureUnitPreference = .fahrenheit

        #expect(model.targetTemperatureLabel == "143°F")
        #expect(!model.canIncreaseTargetTemperatureDraft)

        model.increaseTemperatureDraft()

        #expect(model.targetTemperatureLabel == "143°F")
        #expect(abs(model.targetTemperatureDraftCelsius - ((143.0 - 32.0) * 5.0 / 9.0)) < 0.0001)
    }

    @Test func historyLogsMeaningfulChangesAndSkipsDuplicateReadings() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            appSessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            nowProvider: { now }
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54, batteryLevel: 0.70))
        #expect(historyEvents(for: "MUG-1", in: model).count == 1)

        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54.04, batteryLevel: 0.70))
        #expect(historyEvents(for: "MUG-1", in: model).count == 1)

        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54.2, batteryLevel: 0.70))
        #expect(historyEvents(for: "MUG-1", in: model).count == 2)

        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54.2, batteryLevel: 0.72))
        let events = historyEvents(for: "MUG-1", in: model)

        #expect(events.count == 3)
        #expect(events.last?.batteryPercent == 72)
        #expect(events.last?.temperatureCelsius == 54.2)
    }

    @Test func historyFileStorePersistsAndReloadsJSONLines() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftea-history-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let event = MugHistoryEvent(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            mugIdentifier: "MUG-1",
            appSessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .reading,
            batteryPercent: 71,
            temperatureCelsius: 54.3,
            isHeatingOn: true,
            isConnected: true
        )

        let writer = MugHistoryFileStore(fileURL: fileURL)
        try await writer.append(event)

        let reader = MugHistoryFileStore(fileURL: fileURL)
        let loadedEvents = try await reader.loadEvents()

        #expect(loadedEvents == [event])
    }

    @Test func historyFileStoreRejectsSymlinkedHistoryFileOnAppend() async throws {
        let directoryURL = try temporaryHistoryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let targetURL = directoryURL.appendingPathComponent("target.txt")
        let historyURL = directoryURL.appendingPathComponent("mug-history-v1.jsonl")
        try Data("ORIGINAL\n".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: historyURL, withDestinationURL: targetURL)

        let store = MugHistoryFileStore(fileURL: historyURL)
        await expectHistoryStoreToRejectUnsafePath {
            try await store.append(sampleHistoryEvent())
        }

        let targetContents = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(targetContents == "ORIGINAL\n")
    }

    @Test func historyFileStoreRejectsHardLinkedHistoryFileOnAppend() async throws {
        let directoryURL = try temporaryHistoryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let targetURL = directoryURL.appendingPathComponent("target.txt")
        let historyURL = directoryURL.appendingPathComponent("mug-history-v1.jsonl")
        try Data("ORIGINAL\n".utf8).write(to: targetURL)
        try FileManager.default.linkItem(at: targetURL, to: historyURL)

        let store = MugHistoryFileStore(fileURL: historyURL)
        await expectHistoryStoreToRejectUnsafePath {
            try await store.append(sampleHistoryEvent())
        }

        let targetContents = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(targetContents == "ORIGINAL\n")
    }

    @Test func historyFileStoreRejectsSymlinkedHistoryFileOnReplace() async throws {
        let directoryURL = try temporaryHistoryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let targetURL = directoryURL.appendingPathComponent("target.txt")
        let historyURL = directoryURL.appendingPathComponent("mug-history-v1.jsonl")
        try Data("ORIGINAL\n".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: historyURL, withDestinationURL: targetURL)

        let store = MugHistoryFileStore(fileURL: historyURL)
        await expectHistoryStoreToRejectUnsafePath {
            try await store.replaceEvents([sampleHistoryEvent()])
        }

        let targetContents = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(targetContents == "ORIGINAL\n")
    }

    @Test func historyFileStoreRejectsHardLinkedHistoryFileOnReplace() async throws {
        let directoryURL = try temporaryHistoryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let targetURL = directoryURL.appendingPathComponent("target.txt")
        let historyURL = directoryURL.appendingPathComponent("mug-history-v1.jsonl")
        try Data("ORIGINAL\n".utf8).write(to: targetURL)
        try FileManager.default.linkItem(at: targetURL, to: historyURL)

        let store = MugHistoryFileStore(fileURL: historyURL)
        await expectHistoryStoreToRejectUnsafePath {
            try await store.replaceEvents([sampleHistoryEvent()])
        }

        let targetContents = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(targetContents == "ORIGINAL\n")
    }

    @Test func historyFileStoreRejectsSymlinkedHistoryFileOnLoad() async throws {
        let directoryURL = try temporaryHistoryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let targetURL = directoryURL.appendingPathComponent("target.txt")
        let historyURL = directoryURL.appendingPathComponent("mug-history-v1.jsonl")
        try Data("ORIGINAL\n".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: historyURL, withDestinationURL: targetURL)

        let store = MugHistoryFileStore(fileURL: historyURL)
        await expectHistoryStoreToRejectUnsafePath {
            _ = try await store.loadEvents()
        }
    }

    @Test func historyFileStoreRejectsSymlinkedHistoryDirectory() async throws {
        let baseDirectoryURL = try temporaryHistoryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectoryURL) }

        let realDirectoryURL = baseDirectoryURL.appendingPathComponent("real-history", isDirectory: true)
        let linkedDirectoryURL = baseDirectoryURL.appendingPathComponent("linked-history", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectoryURL, withDestinationURL: realDirectoryURL)

        let store = MugHistoryFileStore(
            fileURL: linkedDirectoryURL.appendingPathComponent("mug-history-v1.jsonl")
        )

        await expectHistoryStoreToRejectUnsafePath {
            try await store.append(sampleHistoryEvent())
        }

        #expect(FileManager.default.fileExists(atPath: realDirectoryURL.appendingPathComponent("mug-history-v1.jsonl").path) == false)
    }

    @Test func historyIsKeptPerMugIdentifier() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1", currentTemperatureCelsius: 54, batteryLevel: 0.70))
        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-2", currentTemperatureCelsius: 55, batteryLevel: 0.80))

        #expect(Set(historyEvents(for: "MUG-1", in: model).map(\.mugIdentifier)) == ["MUG-1"])
        #expect(Set(historyEvents(for: "MUG-2", in: model).map(\.mugIdentifier)) == ["MUG-2"])

        let selectedBatteryValues = model.historyChartSegments(metric: .battery, now: now)
            .flatMap(\.points)
            .map(\.value)
        #expect(selectedBatteryValues.allSatisfy { $0 == 70 })

        model.selectSidebarMug(identifier: "MUG-2")

        let secondMugBatteryValues = model.historyChartSegments(metric: .battery, now: now)
            .flatMap(\.points)
            .map(\.value)
        #expect(secondMugBatteryValues.allSatisfy { $0 == 80 })
    }

    @Test func backgroundMugSnapshotDoesNotStealSelectedDashboard() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1", currentTemperatureCelsius: 54, batteryLevel: 0.70))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 59, activePeripheralIdentifier: "MUG-2", currentTemperatureCelsius: 55, batteryLevel: 0.80))

        #expect(model.shouldShowMugDashboard)
        #expect(model.selectedMugIdentifier == "MUG-1")
        #expect(model.activePeripheralIdentifier == "MUG-1")
        #expect(model.currentTemperatureCelsius == 54)
        #expect(model.batteryLevel == 0.70)
        #expect(Set(model.sidebarMugs.map(\.identifier)) == ["MUG-1", "MUG-2"])
        #expect(Set(model.connectedSidebarMugs.map(\.identifier)) == ["MUG-1", "MUG-2"])
        #expect(model.savedSidebarMugs.isEmpty)

        model.selectSidebarMug(identifier: "MUG-2")

        #expect(model.shouldShowMugDashboard)
        #expect(model.selectedMugIdentifier == "MUG-2")
        #expect(model.activePeripheralIdentifier == "MUG-2")
        #expect(model.currentTemperatureCelsius == 55)
        #expect(model.batteryLevel == 0.80)
    }

    @Test func targetDraftsAreRememberedPerMug() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))
        model.setTargetTemperatureDraft(to: 51, reenableIfNeeded: true)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 59, activePeripheralIdentifier: "MUG-2"))
        model.selectSidebarMug(identifier: "MUG-2")
        model.setTargetTemperatureDraft(to: 56, reenableIfNeeded: true)

        model.selectSidebarMug(identifier: "MUG-1")
        #expect(model.targetTemperatureDraftCelsius == 51)

        model.selectSidebarMug(identifier: "MUG-2")
        #expect(model.targetTemperatureDraftCelsius == 56)
    }

    @Test func oldPreferredMugMigratesToSelectedAndAutoConnectList() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("MUG-A", forKey: AppPreferencesKey.preferredPeripheralIdentifier)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(model.selectedMugIdentifier == "MUG-A")
        #expect(model.savedMugIdentifiers == ["MUG-A"])
        #expect(model.autoConnectMugIdentifiers == ["MUG-A"])
        #expect(model.defaultSidebarSelectionIdentifier == "MUG-A")
    }

    @Test func savedMugCanDisableAutoConnectWithoutDisappearingFromSidebar() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.autoConnectMugIdentifiers
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.setAutoConnectEnabled(false, for: "MUG-SAVED")

        #expect(model.savedMugIdentifiers == ["MUG-SAVED"])
        #expect(model.autoConnectMugIdentifiers.isEmpty)
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-SAVED"])
        #expect(preferences.string(forKey: AppPreferencesKey.savedMugIdentifiers)?.contains("MUG-SAVED") == true)
        #expect(preferences.string(forKey: AppPreferencesKey.autoConnectMugIdentifiers) == nil)
    }

    @Test func manualConnectDoesNotReenableAutoConnect() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.connectSidebarMug(identifier: "MUG-SAVED")
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-SAVED"))

        #expect(model.savedMugIdentifiers == ["MUG-SAVED"])
        #expect(!model.autoConnectMugIdentifiers.contains("MUG-SAVED"))
    }

    @Test func manualDisconnectSuppressesEventDrivenReconnectUntilUserConnectsAgain() {
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.autoConnectMugIdentifiers
        )
        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            bluetoothCoordinator: bluetoothCoordinator
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-SAVED"))
        bluetoothCoordinator.recoverAutoConnectMugsCallCount = 0

        model.disconnectSidebarMug(identifier: "MUG-SAVED")
        model.handleReconnectOpportunity()

        #expect(model.autoConnectMugIdentifiers == ["MUG-SAVED"])
        #expect(bluetoothCoordinator.autoConnectIdentifierUpdates.last == [])
        #expect(bluetoothCoordinator.disconnectedMugIdentifiers == ["MUG-SAVED"])
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 0)

        model.connectSidebarMug(identifier: "MUG-SAVED")
        model.handleReconnectOpportunity()

        #expect(model.autoConnectMugIdentifiers == ["MUG-SAVED"])
        #expect(bluetoothCoordinator.autoConnectIdentifierUpdates.last == ["MUG-SAVED"])
        #expect(bluetoothCoordinator.preferredIdentifierUpdates.last == "MUG-SAVED")
        #expect(bluetoothCoordinator.scanForPreferredMugCallCount == 1)
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 1)
    }

    @Test func lostDisconnectRemainsEligibleForEventDrivenReconnect() {
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.autoConnectMugIdentifiers
        )
        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            bluetoothCoordinator: bluetoothCoordinator
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-SAVED"))
        bluetoothCoordinator.recoverAutoConnectMugsCallCount = 0
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: nil,
                discoveryPhase: .disconnected,
                activePeripheralIdentifier: "MUG-SAVED",
                detailMessage: "Connection lost.",
                canWriteTargetTemperature: false
            )
        )

        #expect(model.autoConnectMugIdentifiers == ["MUG-SAVED"])
        #expect(bluetoothCoordinator.autoConnectIdentifierUpdates.last == ["MUG-SAVED"])
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 1)
    }

    @Test func appActivationRefreshesConnectedMugWithoutRestartingItsConnection() {
        let bluetoothCoordinator = RecordingBluetoothCoordinator()
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.autoConnectMugIdentifiers
        )
        let model = AppModel(
            startBluetooth: false,
            preferences: preferences,
            bluetoothCoordinator: bluetoothCoordinator
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-SAVED"))
        bluetoothCoordinator.recoverAutoConnectMugsCallCount = 0
        bluetoothCoordinator.refreshReadingsCallCount = 0

        model.handleReconnectOpportunity()

        #expect(model.shouldShowMugDashboard)
        #expect(bluetoothCoordinator.refreshReadingsCallCount == 1)
        #expect(bluetoothCoordinator.recoverAutoConnectMugsCallCount == 0)
    }

    @Test func manualDisconnectSuppressionPersistsUntilUserConnectsAgain() {
        let firstCoordinator = RecordingBluetoothCoordinator()
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.autoConnectMugIdentifiers
        )
        let firstModel = AppModel(
            startBluetooth: false,
            preferences: preferences,
            bluetoothCoordinator: firstCoordinator
        )
        firstModel.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-SAVED"))

        firstModel.disconnectSidebarMug(identifier: "MUG-SAVED")

        #expect(preferences.string(forKey: AppPreferencesKey.manuallyDisconnectedMugIdentifiers)?.contains("MUG-SAVED") == true)

        let secondCoordinator = RecordingBluetoothCoordinator()
        let secondModel = AppModel(
            startBluetooth: false,
            preferences: preferences,
            bluetoothCoordinator: secondCoordinator
        )

        secondModel.handleReconnectOpportunity()

        #expect(secondModel.autoConnectMugIdentifiers == ["MUG-SAVED"])
        #expect(secondCoordinator.autoConnectIdentifierUpdates.last == [])
        #expect(secondCoordinator.recoverAutoConnectMugsCallCount == 0)

        secondModel.connectSidebarMug(identifier: "MUG-SAVED")

        #expect(preferences.string(forKey: AppPreferencesKey.manuallyDisconnectedMugIdentifiers) == nil)
        #expect(secondCoordinator.autoConnectIdentifierUpdates.last == ["MUG-SAVED"])
    }

    @Test func connectingMoreThanThreeMugsIsCappedInTheUI() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-2"))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-3"))

        #expect(model.sidebarMugs.count == 3)
        #expect(model.connectedSidebarMugs.count == 3)
        #expect(!model.canTriggerSidebarScan)
    }

    @Test func disconnectedKnownMugMovesFromConnectedToSavedSidebarSection() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: nil,
                discoveryPhase: .disconnected,
                activePeripheralIdentifier: "MUG-1",
                detailMessage: "Disconnected.",
                canWriteTargetTemperature: false
            )
        )

        #expect(model.connectedSidebarMugs.isEmpty)
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-1"])
        #expect(!model.shouldShowMugDashboard)
    }

    @Test func disconnectSidebarMugMovesItToSavedMugs() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))

        #expect(!model.canConnectSidebarMug(identifier: "MUG-1"))

        model.disconnectSidebarMug(identifier: "MUG-1")

        #expect(model.connectedSidebarMugs.isEmpty)
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-1"])
        #expect(model.canConnectSidebarMug(identifier: "MUG-1"))
        #expect(!model.shouldShowMugDashboard)
    }

    @Test func forgettingConnectedSidebarMugDisconnectsAndRemovesIt() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))
        model.mugNameDraft = "Desk Mug"
        model.saveCurrentMugName()

        model.forgetSidebarMug(identifier: "MUG-1")

        #expect(model.sidebarMugs.isEmpty)
        #expect(model.connectedSidebarMugs.isEmpty)
        #expect(model.savedSidebarMugs.isEmpty)
        #expect(model.selectedMugIdentifier == nil)
        #expect(model.preferredPeripheralIdentifier == nil)
        #expect(!model.hasSavedMugPreference)
        #expect(preferences.string(forKey: AppPreferencesKey.savedMugIdentifiers) == nil)
        #expect(preferences.string(forKey: AppPreferencesKey.savedMugNames) == nil)
        #expect(!model.shouldShowMugDashboard)
    }

    @Test func dashboardSelectsTheOnlyConnectedMugOverSavedDisconnectedSelection() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("MUG-SAVED", forKey: AppPreferencesKey.selectedMugIdentifier)
        preferences.set(
            #"{"namesByIdentifier":{"MUG-SAVED":"Saved Mug"}}"#,
            forKey: AppPreferencesKey.savedMugNames
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        #expect(!model.shouldShowMugDashboard)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-LIVE"))

        #expect(model.shouldShowMugDashboard)
        #expect(model.selectedMugIdentifier == "MUG-LIVE")
        #expect(model.activePeripheralIdentifier == "MUG-LIVE")
    }

    @Test func discoveryWindowShowsOnlyUnsavedNearbyMugs() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"namesByIdentifier":{"MUG-SAVED":"Saved Mug"}}"#,
            forKey: AppPreferencesKey.savedMugNames
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-LIVE"))
        model.apply(
            snapshot: discoverySnapshot(
                discoveredMugs: [
                    .init(identifier: "MUG-LIVE", name: "Live Mug", rssi: -52, finish: .black, size: .ounce10),
                    .init(identifier: "MUG-SAVED", name: "Saved Mug", rssi: -58, finish: .white, size: .ounce10),
                    .init(identifier: "MUG-NEW", name: "Ember Mug 2", rssi: -61, finish: .sandstone, size: .ounce14)
                ]
            )
        )

        #expect(model.discoveryWindowMugs.map(\.identifier) == ["MUG-NEW"])
        #expect(model.discoveryWindowMugs.first?.name == "Ember Mug 2")
        #expect(model.discoveryWindowMugs.first?.metadata == "Sandstone • 14 oz")
    }

    @Test func discoveryWindowExcludesSavedMugsEvenWhenAutoConnectIsOff() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"identifiers":["MUG-SAVED"]}"#,
            forKey: AppPreferencesKey.savedMugIdentifiers
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(
            snapshot: discoverySnapshot(
                discoveredMugs: [
                    .init(identifier: "MUG-SAVED", name: "Ember Mug 2", rssi: -58, finish: .white, size: .ounce10),
                    .init(identifier: "MUG-NEW", name: "Ember Mug 2", rssi: -61, finish: .sandstone, size: .ounce14)
                ]
            )
        )

        #expect(model.discoveryWindowMugs.map(\.identifier) == ["MUG-NEW"])
    }

    @Test func discoveryWindowHidesLikelyDuplicateOfConnectedMug() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                activePeripheralIdentifier: "MUG-LIVE",
                currentTemperatureCelsius: 54,
                batteryLevel: 0.70
            )
        )
        model.apply(
            snapshot: discoverySnapshot(
                discoveredMugs: [
                    .init(identifier: "MUG-DUPLICATE", name: "Ember Mug 2", rssi: -45, finish: .black, size: .ounce10),
                    .init(identifier: "MUG-NEW", name: "Ember Mug 2", rssi: -61, finish: .sandstone, size: .ounce14)
                ]
            )
        )

        #expect(model.discoveryWindowMugs.map(\.identifier) == ["MUG-NEW"])
    }

    @Test func connectingDiscoveryMugDoesNotStealExistingConnectedDashboard() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-LIVE"))
        model.apply(
            snapshot: discoverySnapshot(
                discoveredMugs: [
                    .init(identifier: "MUG-NEW", name: "Ember Mug 2", rssi: -61, finish: .sandstone, size: .ounce14)
                ]
            )
        )

        model.connectDiscoveryMug(identifier: "MUG-NEW")

        #expect(model.selectedMugIdentifier == "MUG-LIVE")
        #expect(model.shouldShowMugDashboard)
        #expect(model.savedMugIdentifiers.contains("MUG-NEW"))
        #expect(model.autoConnectMugIdentifiers.contains("MUG-NEW"))
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-NEW"])
        #expect(model.discoveryWindowMugs.isEmpty)
    }

    @Test func selectingConnectingSavedMugDoesNotJumpBackToConnectedDashboard() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-LIVE"))
        model.apply(
            snapshot: discoverySnapshot(
                discoveredMugs: [
                    .init(identifier: "MUG-NEW", name: "Ember Mug 2", rssi: -61, finish: .sandstone, size: .ounce14)
                ]
            )
        )
        model.connectDiscoveryMug(identifier: "MUG-NEW")
        model.apply(snapshot: connectingSnapshot(activePeripheralIdentifier: "MUG-NEW"))

        model.selectSidebarMug(identifier: "MUG-NEW")
        model.apply(snapshot: connectingSnapshot(activePeripheralIdentifier: "MUG-NEW"))

        #expect(model.selectedMugIdentifier == "MUG-NEW")
        #expect(!model.shouldShowMugDashboard)
        #expect(model.connectedSidebarMugs.map(\.identifier) == ["MUG-LIVE"])
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-NEW"])
    }

    @Test func duplicateSerialFromDiscoveryIsMergedIntoExistingMug() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                activePeripheralIdentifier: "MUG-LIVE",
                serialNumber: "PBBG14105067"
            )
        )
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                activePeripheralIdentifier: "MUG-DUPLICATE",
                serialNumber: "PBBG14105067"
            )
        )

        #expect(model.selectedMugIdentifier == "MUG-LIVE")
        #expect(model.connectedSidebarMugs.map(\.identifier) == ["MUG-LIVE"])
        #expect(!model.autoConnectMugIdentifiers.contains("MUG-DUPLICATE"))
        #expect(!model.allSidebarMugIdentifiers.contains("MUG-DUPLICATE"))
    }

    @Test func pendingDiscoveryDuplicateDoesNotReplaceExistingMugWhenExistingSerialArrivesLater() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                activePeripheralIdentifier: "MUG-LIVE",
                serialNumber: ""
            )
        )
        model.apply(
            snapshot: discoverySnapshot(
                discoveredMugs: [
                    .init(identifier: "MUG-DUPLICATE", name: "Ember Mug 2", rssi: -61, finish: .sandstone, size: .ounce14)
                ]
            )
        )
        model.connectDiscoveryMug(identifier: "MUG-DUPLICATE")
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                activePeripheralIdentifier: "MUG-DUPLICATE",
                serialNumber: "PBBG14105067"
            )
        )
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: 58,
                activePeripheralIdentifier: "MUG-LIVE",
                serialNumber: "PBBG14105067"
            )
        )

        #expect(model.selectedMugIdentifier == "MUG-LIVE")
        #expect(model.connectedSidebarMugs.map(\.identifier) == ["MUG-LIVE"])
        #expect(!model.autoConnectMugIdentifiers.contains("MUG-DUPLICATE"))
        #expect(!model.allSidebarMugIdentifiers.contains("MUG-DUPLICATE"))
    }

    @Test func emptyAutomationRunsIndependentlyPerMug() {
        let soundPlayer = SpyHeatingToggleSoundPlayer()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            heatingToggleSoundPlayer: soundPlayer
        )

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1", isEmpty: false))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-2", isEmpty: false))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, activePeripheralIdentifier: "MUG-2", isEmpty: true))

        model.selectSidebarMug(identifier: "MUG-1")
        #expect(!model.isTemperatureControlOff)

        model.selectSidebarMug(identifier: "MUG-2")
        #expect(model.isTemperatureControlOff)
        #expect(soundPlayer.events == [true, true, false])
    }

    @Test func idleSleepPreventionStaysEnabledWhileAnyMugIsConnected() {
        let idleSleepPreventionManager = RecordingIdleSleepPreventionManager()
        let model = AppModel(
            startBluetooth: false,
            preferences: InMemoryAppPreferencesStore(),
            idleSleepPreventionManager: idleSleepPreventionManager
        )

        #expect(!idleSleepPreventionManager.isEnabled)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-2"))

        #expect(idleSleepPreventionManager.isEnabled)

        model.disconnectSidebarMug(identifier: "MUG-1")

        #expect(idleSleepPreventionManager.isEnabled)

        model.disconnectSidebarMug(identifier: "MUG-2")

        #expect(!idleSleepPreventionManager.isEnabled)
    }

    @Test func chartSamplesRespectSelectedTimeframe() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })
        let finalNow = now.addingTimeInterval(2 * 60 * 60)

        model.chartTimeframePreference = .oneHour
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54, batteryLevel: 0.70))

        now = finalNow
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 55, batteryLevel: 0.75))

        let windowStart = finalNow.addingTimeInterval(-model.chartTimeframePreference.duration)
        let points = model.historyChartSegments(metric: .battery, now: finalNow).flatMap(\.points)

        #expect(!points.isEmpty)
        #expect(points.allSatisfy { $0.timestamp >= windowStart && $0.timestamp <= finalNow })
    }

    @Test func chartBreaksLinesAcrossDisconnects() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54, batteryLevel: 0.70))
        now = now.addingTimeInterval(60)
        model.apply(
            snapshot: connectedSnapshot(
                targetTemperatureCelsius: nil,
                discoveryPhase: .disconnected,
                canWriteTargetTemperature: false,
                currentTemperatureCelsius: nil,
                batteryLevel: nil
            )
        )
        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 55, batteryLevel: 0.69))

        let segments = model.historyChartSegments(metric: .battery, now: now)

        #expect(segments.count == 2)
    }

    @Test func temperatureChartOmitsHeatingOffPeriods() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 54, batteryLevel: 0.70))
        now = now.addingTimeInterval(60)
        model.setTemperatureControlEnabled(false)
        let heatingOffAt = now
        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 0, currentTemperatureCelsius: 55, batteryLevel: 0.70))

        let points = model.historyChartSegments(metric: .temperature, now: now).flatMap(\.points)

        #expect(points.allSatisfy { $0.timestamp < heatingOffAt })
    }

    @Test func chartTimeframePreferencePersistsWhenChanged() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.chartTimeframePreference = .twentyFourHours

        #expect(preferences.string(forKey: AppPreferencesKey.chartTimeframePreference) == "twentyFourHours")
    }

    @Test func timeFormatPreferencePersistsWhenChanged() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.timeFormatPreference = .twelveHour

        #expect(preferences.string(forKey: AppPreferencesKey.timeFormatPreference) == "twelveHour")
    }

    @Test func chartTimeLabelsRespectSelectedTimeFormat() throws {
        let date = Date(timeIntervalSince1970: 15 * 60 * 60 + 5 * 60)
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US_POSIX")

        #expect(
            AppModel.formatTime(
                date,
                preference: .twentyFourHour,
                timeZone: timeZone,
                locale: locale
            ) == "15:05"
        )
        #expect(
            AppModel.formatTime(
                date,
                preference: .twelveHour,
                timeZone: timeZone,
                locale: locale
            ) == "3:05\npm"
        )
    }

    @Test func chartTimeLabelsRespectSelectedTimeFormatWithRegularUserLocale() throws {
        let date = Date(timeIntervalSince1970: 15 * 60 * 60 + 5 * 60)
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US")

        #expect(
            AppModel.formatTime(
                date,
                preference: .twentyFourHour,
                timeZone: timeZone,
                locale: locale
            ) == "15:05"
        )
        #expect(
            AppModel.formatTime(
                date,
                preference: .twelveHour,
                timeZone: timeZone,
                locale: locale
            ) == "3:05\npm"
        )
    }

    @Test func chartXAxisLayoutDoesNotMoveBetweenTimeFormats() {
        #expect(AppModel.TimeFormatPreference.twentyFourHour.chartXAxisLabelWidth == AppModel.TimeFormatPreference.twelveHour.chartXAxisLabelWidth)
        #expect(AppModel.TimeFormatPreference.twelveHour.chartXAxisLabelFontSize < AppModel.TimeFormatPreference.twentyFourHour.chartXAxisLabelFontSize)
    }

    @Test func twelveHourChartMeridiemLabelIsOnePointSmallerThanTimeLabel() {
        #expect(
            AppModel.TimeFormatPreference.twelveHour.chartXAxisMeridiemLabelFontSize
                == AppModel.TimeFormatPreference.twelveHour.chartXAxisLabelFontSize - 1
        )
    }

    @Test func twelveHourChartLabelFitsStableAxisSlot() {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: AppModel.TimeFormatPreference.twelveHour.chartXAxisLabelFontSize,
            weight: .regular
        )
        let widestExpectedLabel = "12:59" as NSString
        let labelWidth = widestExpectedLabel.size(withAttributes: [.font: font]).width

        #expect(labelWidth <= AppModel.TimeFormatPreference.twelveHour.chartXAxisLabelWidth)
    }

    @Test func keepRunningWhenWindowClosedPreferencePersistsWhenChanged() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.keepsRunningWhenWindowClosed = false

        #expect(preferences.bool(forKey: AppPreferencesKey.keepsRunningWhenWindowClosed) == false)
    }

    @Test func appLocationPreferencePersistsWhenChanged() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.appLocationPreference = .dock

        #expect(preferences.string(forKey: AppPreferencesKey.appLocationPreference) == "dock")
    }

    @Test func temperatureChartUsesFahrenheitDisplayValuesWhenPreferred() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore(), nowProvider: { now })

        model.temperatureUnitPreference = .fahrenheit
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 50, batteryLevel: 0.70))
        now = now.addingTimeInterval(60)
        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, currentTemperatureCelsius: 51, batteryLevel: 0.70))

        let values = model.historyChartSegments(metric: .temperature, now: now).flatMap(\.points).map(\.value)

        #expect(values.contains(AppModel.temperatureDisplayValue(celsius: 50, unit: .fahrenheit)))
        #expect(values.contains(AppModel.temperatureDisplayValue(celsius: 51, unit: .fahrenheit)))
    }

    @Test func discoveredDeviceNameIsPersisted() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-1",
                discoveredDeviceName: "Desk Mug",
                discoveredDeviceFinish: .copper,
                discoveredDeviceSize: .ounce14,
                serialNumber: "PBAB98765432",
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "Connected.",
                currentTemperatureCelsius: 54,
                targetTemperatureCelsius: 58,
                batteryLevel: 0.7,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: false,
                canReadCurrentTemperature: true,
                canReadTargetTemperature: true,
                canReadBattery: true,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: false,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(preferences.string(forKey: AppPreferencesKey.lastKnownDeviceName) == "Desk Mug")
        #expect(model.deviceFinish == .copper)
        #expect(model.deviceSize == .ounce14)
        #expect(model.deviceSerialNumber == "PBAB98765432")
    }

    @Test func forgettingSavedMugClearsPreference() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set("ABC-123", forKey: AppPreferencesKey.preferredPeripheralIdentifier)

        let model = AppModel(startBluetooth: false, preferences: preferences)
        #expect(model.hasSavedMugPreference)

        model.forgetSavedMug()

        #expect(model.preferredPeripheralIdentifier == nil)
        #expect(preferences.string(forKey: AppPreferencesKey.preferredPeripheralIdentifier) == nil)
    }

    @Test func sidebarSplitsConnectedAndSavedMugsAndOmitsNearbyMugs() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"namesByIdentifier":{"MUG-A":"Desk Mug","MUG-B":"Kitchen Mug","MUG-C":"Studio Mug"}}"#,
            forKey: AppPreferencesKey.savedMugNames
        )
        preferences.set("MUG-A", forKey: AppPreferencesKey.preferredPeripheralIdentifier)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-A",
                discoveredDeviceName: "Ember Mug 2",
                discoveredDeviceFinish: .black,
                discoveredDeviceSize: .ounce10,
                serialNumber: nil,
                discoveredMugs: [
                    .init(identifier: "MUG-A", name: "Ember Mug 2", rssi: -55, finish: .black, size: .ounce10),
                    .init(identifier: "MUG-B", name: "Kitchen Mug", rssi: -63, finish: .copper, size: .ounce14)
                ],
                isScanning: false,
                detailMessage: "Connected.",
                currentTemperatureCelsius: 54,
                targetTemperatureCelsius: 58,
                batteryLevel: 0.7,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: false,
                canReadCurrentTemperature: true,
                canReadTargetTemperature: true,
                canReadBattery: true,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: false,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.currentSidebarMug?.identifier == "MUG-A")
        #expect(model.currentSidebarMug?.name == "Desk Mug")
        #expect(model.connectedSidebarMugs.map(\.identifier) == ["MUG-A"])
        #expect(model.savedSidebarMugs.map(\.identifier) == ["MUG-B", "MUG-C"])
        #expect(model.allSidebarMugIdentifiers == Set(["MUG-A", "MUG-B", "MUG-C"]))
        #expect(model.defaultSidebarSelectionIdentifier == "MUG-A")
    }

    @Test func selectingSavedSidebarMugUpdatesPreferredIdentifier() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"namesByIdentifier":{"MUG-C":"Studio Mug"}}"#,
            forKey: AppPreferencesKey.savedMugNames
        )

        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.selectSidebarMug(identifier: "MUG-C")

        #expect(model.preferredPeripheralIdentifier == "MUG-C")
        #expect(preferences.string(forKey: AppPreferencesKey.preferredPeripheralIdentifier) == "MUG-C")
        #expect(model.deviceName == "Studio Mug")
    }

    @Test func reselectingSelectedSidebarMugIsPassive() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(snapshot: connectedSnapshot(targetTemperatureCelsius: 58, activePeripheralIdentifier: "MUG-1"))
        preferences.set("Sentinel", forKey: AppPreferencesKey.lastKnownDeviceName)

        model.selectSidebarMug(identifier: "MUG-1")

        #expect(model.selectedMugIdentifier == "MUG-1")
        #expect(model.activePeripheralIdentifier == "MUG-1")
        #expect(preferences.string(forKey: AppPreferencesKey.lastKnownDeviceName) == "Sentinel")
    }

    @Test func multipleDiscoveredMugsStayInternalWhenChoosingStateIsReported() {
        let model = AppModel(startBluetooth: false, preferences: InMemoryAppPreferencesStore())

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .choosing,
                activePeripheralIdentifier: nil,
                discoveredDeviceName: nil,
                discoveredDeviceFinish: nil,
                discoveredDeviceSize: nil,
                serialNumber: nil,
                discoveredMugs: [
                    .init(identifier: "A", name: "Kitchen Mug", rssi: -55, finish: .black, size: .ounce10),
                    .init(identifier: "B", name: "Office Mug", rssi: -62, finish: .copper, size: .ounce14)
                ],
                isScanning: false,
                detailMessage: "Multiple Ember mugs found. Choose the one you want to connect to.",
                currentTemperatureCelsius: nil,
                targetTemperatureCelsius: nil,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: nil,
                canReadCurrentTemperature: false,
                canReadTargetTemperature: false,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: false,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.connectionState == .choosing)
        #expect(!model.shouldShowDiscoveredMugs)
        #expect(model.discoveredMugs.count == 2)
        #expect(model.connectionActionTitle == "Retry Scan")
    }

    @Test func savingCurrentMugNamePersistsAliasForConnectedMug() {
        let preferences = InMemoryAppPreferencesStore()
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .connected,
                activePeripheralIdentifier: "MUG-ALIAS",
                discoveredDeviceName: "Ember Ceramic Mug",
                discoveredDeviceFinish: .white,
                discoveredDeviceSize: .ounce14,
                serialNumber: "PBZZ12345678",
                discoveredMugs: [],
                isScanning: false,
                detailMessage: "Connected.",
                currentTemperatureCelsius: nil,
                targetTemperatureCelsius: nil,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: nil,
                canReadCurrentTemperature: false,
                canReadTargetTemperature: false,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: false,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        model.beginEditingCurrentMugName()
        model.mugNameDraft = "Office mug"
        model.saveCurrentMugName()

        #expect(model.deviceName == "Office mug")
        #expect(model.currentMugCustomName == "Office mug")
        #expect(preferences.string(forKey: AppPreferencesKey.savedMugNames)?.contains("Office mug") == true)
    }

    @Test func renamingSavedSidebarMugPersistsAliasWithoutConnectingIt() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"namesByIdentifier":{"MUG-SAVED":"Desk mug"}}"#,
            forKey: AppPreferencesKey.savedMugNames
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.beginEditingSidebarMugName(identifier: "MUG-SAVED")

        #expect(!model.isPresentingMugNameSheet)
        #expect(model.sidebarMugNameEditingIdentifier == "MUG-SAVED")
        #expect(model.sidebarMugNameDraft == "Desk mug")

        model.sidebarMugNameDraft = "Office mug"
        model.commitSidebarMugNameRename()

        #expect(model.sidebarMugNameEditingIdentifier == nil)
        #expect(model.savedSidebarMugs.first?.name == "Office mug")
        #expect(model.connectedSidebarMugs.isEmpty)
        #expect(preferences.string(forKey: AppPreferencesKey.savedMugNames)?.contains("Office mug") == true)
    }

    @Test func mugNameDraftsAreLimitedToEighteenCharacters() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(
            #"{"namesByIdentifier":{"MUG-SAVED":"Desk mug"}}"#,
            forKey: AppPreferencesKey.savedMugNames
        )
        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.beginEditingSidebarMugName(identifier: "MUG-SAVED")
        model.sidebarMugNameDraft = "12345678901234567890"
        model.commitSidebarMugNameRename()

        #expect(model.savedSidebarMugs.first?.name == "123456789012345678")
    }

    @Test func savedMugAliasAppliesToFutureDiscoveries() {
        let preferences = InMemoryAppPreferencesStore()
        preferences.set(#"{"namesByIdentifier":{"MUG-ALIAS":"Kitchen mug"}}"#, forKey: AppPreferencesKey.savedMugNames)

        let model = AppModel(startBluetooth: false, preferences: preferences)

        model.apply(
            snapshot: BluetoothRuntimeSnapshot(
                authorization: .allowed,
                hardwareState: .poweredOn,
                discoveryPhase: .choosing,
                activePeripheralIdentifier: nil,
                discoveredDeviceName: nil,
                discoveredDeviceFinish: nil,
                discoveredDeviceSize: nil,
                serialNumber: nil,
                discoveredMugs: [
                    .init(identifier: "MUG-ALIAS", name: "Ember Ceramic Mug", rssi: -50, finish: .black, size: .ounce10),
                    .init(identifier: "MUG-RAW", name: "Ember Ceramic Mug", rssi: -65, finish: .copper, size: .ounce14)
                ],
                isScanning: false,
                detailMessage: "Choose a mug.",
                currentTemperatureCelsius: nil,
                targetTemperatureCelsius: nil,
                batteryLevel: nil,
                isCharging: false,
                contentsLevelRaw: nil,
                liquidStateDescription: nil,
                isEmpty: nil,
                canReadCurrentTemperature: false,
                canReadTargetTemperature: false,
                canReadBattery: false,
                canReadContents: false,
                canReadActivity: false,
                canWriteTargetTemperature: false,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )

        #expect(model.discoveredMugs[0].name == "Kitchen mug")
        #expect(model.discoveredMugs[1].name == "Ember Ceramic Mug")
    }

    @MainActor
    private final class RecordingBluetoothCoordinator: EmberMugBluetoothCoordinating {
        struct TargetWrite: Equatable {
            let celsius: Double?
            let identifier: String?
        }

        var targetWrites: [TargetWrite] = []
        var preferredIdentifierUpdates: [String?] = []
        var autoConnectIdentifierUpdates: [[String]] = []
        var recoverAutoConnectMugsCallCount = 0
        var refreshReadingsCallCount = 0
        var scanForPreferredMugCallCount = 0
        var disconnectedMugIdentifiers: [String] = []

        func retryScan() {}
        func setPreferredPeripheralIdentifier(_ identifier: String?) {
            preferredIdentifierUpdates.append(identifier)
        }

        func setAutoConnectPeripheralIdentifiers(_ identifiers: [String]) {
            autoConnectIdentifierUpdates.append(identifiers)
        }

        func recoverAutoConnectMugs() {
            recoverAutoConnectMugsCallCount += 1
        }

        func connectToCandidate(identifier: String) {}
        func stopDiscoveryScan() {}
        func scanForPreferredMug() {
            scanForPreferredMugCallCount += 1
        }

        func disconnectMug(identifier: String) {
            disconnectedMugIdentifiers.append(identifier)
        }

        func forgetMug(identifier: String) {}
        func startDiscoveryScan(excluding identifiers: [String]) {}
        func refreshReadings() {
            refreshReadingsCallCount += 1
        }
        func refreshReadings(for identifier: String?) {}

        func setTargetTemperature(_ celsius: Double?, for identifier: String?) {
            targetWrites.append(.init(celsius: celsius, identifier: identifier))
        }
    }

    @MainActor
    private final class SpyHeatingToggleSoundPlayer: HeatingToggleSoundPlaying {
        var events: [Bool] = []

        func playHeatingToggleSound(isEnabled: Bool) {
            events.append(isEnabled)
        }
    }

    @MainActor
    private final class RecordingTargetTemperatureNotifier: TargetTemperatureNotificationDelivering {
        struct Delivery: Equatable {
            let mugName: String
            let targetLabel: String
        }

        enum BatteryEvent: Equatable {
            case fullyCharged(mugName: String)
            case fullyDischarged(mugName: String)
        }

        var authorizationResult = true
        var authorizationRequestCount = 0
        var deliveries: [Delivery] = []
        var batteryEvents: [BatteryEvent] = []

        func requestAuthorizationIfNeeded() async -> Bool {
            authorizationRequestCount += 1
            return authorizationResult
        }

        func deliverTargetReachedNotification(mugName: String, targetLabel: String) async {
            deliveries.append(.init(mugName: mugName, targetLabel: targetLabel))
        }

        func deliverBatteryFullyChargedNotification(mugName: String) async {
            batteryEvents.append(.fullyCharged(mugName: mugName))
        }

        func deliverBatteryFullyDischargedNotification(mugName: String) async {
            batteryEvents.append(.fullyDischarged(mugName: mugName))
        }
    }

    @MainActor
    private final class RecordingIdleSleepPreventionManager: IdleSleepPreventionManaging {
        var isEnabled = false

        func setIdleSleepPreventionEnabled(_ isEnabled: Bool) {
            self.isEnabled = isEnabled
        }
    }

    @MainActor
    private final class RecordingLoginItemManager: LoginItemManaging {
        var status: LoginItemRegistrationStatus
        var requestedValues: [Bool] = []

        init(status: LoginItemRegistrationStatus) {
            self.status = status
        }

        func setEnabled(_ isEnabled: Bool) throws {
            requestedValues.append(isEnabled)
            status = isEnabled ? .enabled : .disabled
        }

        func openSystemSettings() {}
    }

    private func connectedSnapshot(
        targetTemperatureCelsius: Double?,
        discoveryPhase: BluetoothRuntimeSnapshot.DiscoveryPhase = .connected,
        activePeripheralIdentifier: String = "MUG-1",
        detailMessage: String = "Connected.",
        canWriteTargetTemperature: Bool = true,
        isEmpty: Bool = false,
        currentTemperatureCelsius: Double? = 54,
        batteryLevel: Double? = 0.7,
        isCharging: Bool = false,
        serialNumber: String? = nil
    ) -> BluetoothRuntimeSnapshot {
        let resolvedSerialNumber = serialNumber ?? {
            if activePeripheralIdentifier == "MUG-1" {
                return "PBBG14105067"
            }

            return "PBBG14105067-\(activePeripheralIdentifier)"
        }()

        return BluetoothRuntimeSnapshot(
            authorization: .allowed,
            hardwareState: .poweredOn,
            discoveryPhase: discoveryPhase,
            activePeripheralIdentifier: activePeripheralIdentifier,
            discoveredDeviceName: "Ember Mug 2",
            discoveredDeviceFinish: .black,
            discoveredDeviceSize: .ounce10,
            serialNumber: resolvedSerialNumber,
            discoveredMugs: [],
            isScanning: false,
            detailMessage: detailMessage,
            currentTemperatureCelsius: currentTemperatureCelsius,
            targetTemperatureCelsius: targetTemperatureCelsius,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            contentsLevelRaw: nil,
            liquidStateDescription: nil,
            isEmpty: isEmpty,
            canReadCurrentTemperature: true,
            canReadTargetTemperature: targetTemperatureCelsius != nil,
            canReadBattery: true,
            canReadContents: false,
            canReadActivity: false,
            canWriteTargetTemperature: canWriteTargetTemperature,
            lastConnectedAt: nil,
            lastReadingAt: nil,
            lastTargetWriteAt: nil
        )
    }

    private func connectingSnapshot(activePeripheralIdentifier: String) -> BluetoothRuntimeSnapshot {
        BluetoothRuntimeSnapshot(
            authorization: .allowed,
            hardwareState: .poweredOn,
            discoveryPhase: .connecting,
            activePeripheralIdentifier: activePeripheralIdentifier,
            discoveredDeviceName: "Ember Mug 2",
            discoveredDeviceFinish: .sandstone,
            discoveredDeviceSize: .ounce14,
            serialNumber: nil,
            discoveredMugs: [],
            isScanning: false,
            detailMessage: "Connecting.",
            currentTemperatureCelsius: nil,
            targetTemperatureCelsius: nil,
            batteryLevel: nil,
            isCharging: false,
            contentsLevelRaw: nil,
            liquidStateDescription: nil,
            isEmpty: nil,
            canReadCurrentTemperature: false,
            canReadTargetTemperature: false,
            canReadBattery: false,
            canReadContents: false,
            canReadActivity: false,
            canWriteTargetTemperature: false,
            lastConnectedAt: nil,
            lastReadingAt: nil,
            lastTargetWriteAt: nil
        )
    }

    private func discoverySnapshot(
        discoveredMugs: [BluetoothRuntimeSnapshot.DiscoveredMug],
        isScanning: Bool = true,
        detailMessage: String = "Looking for nearby Ember mugs."
    ) -> BluetoothRuntimeSnapshot {
        BluetoothRuntimeSnapshot(
            authorization: .allowed,
            hardwareState: .poweredOn,
            discoveryPhase: .scanning,
            activePeripheralIdentifier: nil,
            discoveredDeviceName: nil,
            discoveredDeviceFinish: nil,
            discoveredDeviceSize: nil,
            serialNumber: nil,
            discoveredMugs: discoveredMugs,
            isScanning: isScanning,
            detailMessage: detailMessage,
            currentTemperatureCelsius: nil,
            targetTemperatureCelsius: nil,
            batteryLevel: nil,
            isCharging: false,
            contentsLevelRaw: nil,
            liquidStateDescription: nil,
            isEmpty: nil,
            canReadCurrentTemperature: false,
            canReadTargetTemperature: false,
            canReadBattery: false,
            canReadContents: false,
            canReadActivity: false,
            canWriteTargetTemperature: false,
            lastConnectedAt: nil,
            lastReadingAt: nil,
            lastTargetWriteAt: nil
        )
    }

    private func historyEvents(for mugIdentifier: String, in model: AppModel) -> [MugHistoryEvent] {
        model.mugHistoryEvents
            .filter { $0.mugIdentifier == mugIdentifier }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func temporaryHistoryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftea-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func sampleHistoryEvent() -> MugHistoryEvent {
        MugHistoryEvent(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            mugIdentifier: "MUG-1",
            appSessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .reading,
            batteryPercent: 71,
            temperatureCelsius: 54.3,
            isHeatingOn: true,
            isConnected: true
        )
    }

    private func expectHistoryStoreToRejectUnsafePath(_ operation: () async throws -> Void) async {
        var didThrow = false
        do {
            try await operation()
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

}
