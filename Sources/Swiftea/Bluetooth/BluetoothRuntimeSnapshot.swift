import Foundation

struct BluetoothRuntimeSnapshot: Equatable {
    struct DiscoveredMug: Identifiable, Equatable {
        let identifier: String
        let name: String
        let rssi: Int
        let finish: EmberMugFinish?
        let size: EmberMugSize?

        var id: String { identifier }

        var signalLabel: String {
            guard rssi != 127 else { return "Signal unknown" }
            return "\(rssi) dBm"
        }
    }

    enum AuthorizationStatus: Equatable {
        case allowed
        case notDetermined
        case denied
        case restricted

        var title: String {
            switch self {
            case .allowed:
                "Allowed"
            case .notDetermined:
                "Not determined"
            case .denied:
                "Denied"
            case .restricted:
                "Restricted"
            }
        }
    }

    enum HardwareState: Equatable {
        case unknown
        case resetting
        case unsupported
        case unauthorized
        case poweredOff
        case poweredOn

        var title: String {
            switch self {
            case .unknown:
                "Checking"
            case .resetting:
                "Resetting"
            case .unsupported:
                "Unsupported"
            case .unauthorized:
                "Unauthorized"
            case .poweredOff:
                "Powered off"
            case .poweredOn:
                "Powered on"
            }
        }
    }

    enum DiscoveryPhase: Equatable {
        case starting
        case idle
        case scanning
        case choosing
        case connecting
        case connected
        case disconnected
        case failed

        var title: String {
            switch self {
            case .starting:
                "Starting"
            case .idle:
                "Idle"
            case .scanning:
                "Scanning"
            case .choosing:
                "Choose mug"
            case .connecting:
                "Connecting"
            case .connected:
                "Connected"
            case .disconnected:
                "Disconnected"
            case .failed:
                "Failed"
            }
        }
    }

    let authorization: AuthorizationStatus
    let hardwareState: HardwareState
    let discoveryPhase: DiscoveryPhase
    let activePeripheralIdentifier: String?
    let discoveredDeviceName: String?
    let discoveredDeviceFinish: EmberMugFinish?
    let discoveredDeviceSize: EmberMugSize?
    let serialNumber: String?
    let discoveredMugs: [DiscoveredMug]
    let isScanning: Bool
    let detailMessage: String
    let currentTemperatureCelsius: Double?
    let targetTemperatureCelsius: Double?
    let batteryLevel: Double?
    let isCharging: Bool
    let contentsLevelRaw: Int?
    let liquidStateDescription: String?
    let isEmpty: Bool?
    let canReadCurrentTemperature: Bool
    let canReadTargetTemperature: Bool
    let canReadBattery: Bool
    let canReadContents: Bool
    let canReadActivity: Bool
    let canWriteTargetTemperature: Bool
    let lastBatteryReadingAt: Date?
    let lastConnectedAt: Date?
    let lastReadingAt: Date?
    let lastTargetWriteAt: Date?

    init(
        authorization: AuthorizationStatus,
        hardwareState: HardwareState,
        discoveryPhase: DiscoveryPhase,
        activePeripheralIdentifier: String?,
        discoveredDeviceName: String?,
        discoveredDeviceFinish: EmberMugFinish?,
        discoveredDeviceSize: EmberMugSize?,
        serialNumber: String?,
        discoveredMugs: [DiscoveredMug],
        isScanning: Bool,
        detailMessage: String,
        currentTemperatureCelsius: Double?,
        targetTemperatureCelsius: Double?,
        batteryLevel: Double?,
        isCharging: Bool,
        contentsLevelRaw: Int?,
        liquidStateDescription: String?,
        isEmpty: Bool?,
        canReadCurrentTemperature: Bool,
        canReadTargetTemperature: Bool,
        canReadBattery: Bool,
        canReadContents: Bool,
        canReadActivity: Bool,
        canWriteTargetTemperature: Bool,
        lastBatteryReadingAt: Date? = nil,
        lastConnectedAt: Date?,
        lastReadingAt: Date?,
        lastTargetWriteAt: Date?
    ) {
        self.authorization = authorization
        self.hardwareState = hardwareState
        self.discoveryPhase = discoveryPhase
        self.activePeripheralIdentifier = activePeripheralIdentifier
        self.discoveredDeviceName = discoveredDeviceName
        self.discoveredDeviceFinish = discoveredDeviceFinish
        self.discoveredDeviceSize = discoveredDeviceSize
        self.serialNumber = serialNumber
        self.discoveredMugs = discoveredMugs
        self.isScanning = isScanning
        self.detailMessage = detailMessage
        self.currentTemperatureCelsius = currentTemperatureCelsius
        self.targetTemperatureCelsius = targetTemperatureCelsius
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.contentsLevelRaw = contentsLevelRaw
        self.liquidStateDescription = liquidStateDescription
        self.isEmpty = isEmpty
        self.canReadCurrentTemperature = canReadCurrentTemperature
        self.canReadTargetTemperature = canReadTargetTemperature
        self.canReadBattery = canReadBattery
        self.canReadContents = canReadContents
        self.canReadActivity = canReadActivity
        self.canWriteTargetTemperature = canWriteTargetTemperature
        self.lastBatteryReadingAt = lastBatteryReadingAt
        self.lastConnectedAt = lastConnectedAt
        self.lastReadingAt = lastReadingAt
        self.lastTargetWriteAt = lastTargetWriteAt
    }
}
