import CoreBluetooth
import Foundation

struct PushReadBudget {
    private var lastRequestAt: [CBUUID: TimeInterval] = [:]

    mutating func admit(_ characteristic: CBUUID, uptime: TimeInterval) -> Bool {
        if let previous = lastRequestAt[characteristic], uptime - previous < 1 { return false }
        lastRequestAt[characteristic] = uptime
        return true
    }
}

struct MugReadingHealth {
    enum Action: Equatable {
        case read
        case reconnect
    }

    private let startedAt: TimeInterval
    private var successfulReads: [CBUUID: TimeInterval] = [:]
    private var staleProbeAt: TimeInterval?

    init(uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        startedAt = uptime
    }

    mutating func record(_ characteristic: CBUUID, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        successfulReads[characteristic] = uptime
    }

    mutating func action(requiredCharacteristics: [CBUUID], uptime: TimeInterval) -> Action {
        let oldestRead = requiredCharacteristics.map { successfulReads[$0] ?? startedAt }.min() ?? uptime
        guard uptime - oldestRead >= 90 else {
            staleProbeAt = nil
            return .read
        }

        // Give a resumed Mac a fresh read before replacing an unresponsive connection.
        guard let staleProbeAt else {
            staleProbeAt = uptime
            return .read
        }
        return uptime - staleProbeAt >= 20 ? .reconnect : .read
    }
}

@MainActor
final class MugConnectionMonitor {
    static let activityOptions: ProcessInfo.ActivityOptions = .userInitiatedAllowingIdleSystemSleep

    private let interval: TimeInterval
    private let onCheck: @MainActor () -> Void
    private let beginActivity: (ProcessInfo.ActivityOptions) -> NSObjectProtocol
    private let endActivity: (NSObjectProtocol) -> Void
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    init(
        interval: TimeInterval = 20,
        beginActivity: @escaping (ProcessInfo.ActivityOptions) -> NSObjectProtocol = {
            ProcessInfo.processInfo.beginActivity(
                options: $0,
                reason: "Swiftea is monitoring mugs and waiting for saved mugs to become available."
            )
        },
        endActivity: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) },
        onCheck: @escaping @MainActor () -> Void
    ) {
        self.interval = interval
        self.beginActivity = beginActivity
        self.endActivity = endActivity
        self.onCheck = onCheck
    }

    isolated deinit {
        timer?.invalidate()
        if let activity { endActivity(activity) }
    }

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard timer == nil else { return }
            activity = beginActivity(Self.activityOptions)
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onCheck() }
            }
            timer.tolerance = min(2, interval / 10)
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            timer?.invalidate()
            timer = nil
            if let activity {
                endActivity(activity)
                self.activity = nil
            }
        }
    }
}

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

    var connectionTimeoutWorkItem: DispatchWorkItem?
    var readingHealth = MugReadingHealth()

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
    var pushReadBudget = PushReadBudget()

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
        readingHealth = MugReadingHealth()
        pushReadBudget = PushReadBudget()
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

    func cancelConnectionTimeout() {
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
    }
}
