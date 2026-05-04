import CoreBluetooth
import Foundation

@MainActor
final class MugPeripheralSession {
    let identifier: UUID
    var peripheral: CBPeripheral

    var name: String
    var finish: EmberMugFinish?
    var size: EmberMugSize?
    var phase: BluetoothRuntimeSnapshot.DiscoveryPhase
    var detailMessage: String

    var currentTemperatureCharacteristic: CBCharacteristic?
    var targetTemperatureCharacteristic: CBCharacteristic?
    var contentsCharacteristic: CBCharacteristic?
    var activityCharacteristic: CBCharacteristic?
    var batteryCharacteristic: CBCharacteristic?
    var serialNumberCharacteristic: CBCharacteristic?
    var pushEventCharacteristic: CBCharacteristic?

    var refreshTimer: Timer?
    var connectionTimeoutWorkItem: DispatchWorkItem?

    var serialNumber: String?
    var currentTemperatureCelsius: Double?
    var targetTemperatureCelsius: Double?
    var batteryLevel: Double?
    var isCharging = false
    var contentsLevelRaw: Int?
    var liquidStateDescription: String?
    var isEmpty: Bool?

    var canReadCurrentTemperature = false
    var canReadTargetTemperature = false
    var canReadBattery = false
    var canReadContents = false
    var canReadActivity = false
    var canWriteTargetTemperature = false

    var lastConnectedAt: Date?
    var lastReadingAt: Date?
    var lastBatteryReadingAt: Date?
    var lastTargetWriteAt: Date?

    var pendingTargetWriteCelsius: Double?
    var hasPendingTargetWrite = false

    init(
        peripheral: CBPeripheral,
        name: String,
        finish: EmberMugFinish?,
        size: EmberMugSize?,
        phase: BluetoothRuntimeSnapshot.DiscoveryPhase,
        detailMessage: String
    ) {
        self.identifier = peripheral.identifier
        self.peripheral = peripheral
        self.name = name
        self.finish = finish
        self.size = size
        self.phase = phase
        self.detailMessage = detailMessage
    }

    var isConnected: Bool {
        phase == .connected
    }

    var hasReadableCharacteristics: Bool {
        canReadCurrentTemperature || canReadTargetTemperature || canReadContents || canReadActivity || canReadBattery
    }

    var hasDashboardReading: Bool {
        currentTemperatureCelsius != nil
            || batteryLevel != nil
            || isEmpty != nil
            || contentsLevelRaw != nil
            || liquidStateDescription != nil
    }

    func readableCharacteristics() -> [CBCharacteristic] {
        [
            currentTemperatureCharacteristic,
            targetTemperatureCharacteristic,
            contentsCharacteristic,
            activityCharacteristic,
            batteryCharacteristic,
            serialNumberCharacteristic
        ]
        .compactMap { $0 }
        .filter { $0.properties.contains(.read) }
    }

    func resetLiveReadState(keepConnectionState: Bool) {
        stopPolling()
        currentTemperatureCharacteristic = nil
        targetTemperatureCharacteristic = nil
        contentsCharacteristic = nil
        activityCharacteristic = nil
        batteryCharacteristic = nil
        serialNumberCharacteristic = nil
        pushEventCharacteristic = nil
        serialNumber = nil
        currentTemperatureCelsius = nil
        targetTemperatureCelsius = nil
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
        lastBatteryReadingAt = nil
        hasPendingTargetWrite = false
        pendingTargetWriteCelsius = nil

        if !keepConnectionState {
            phase = .disconnected
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func cancelConnectionTimeout() {
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
    }
}
