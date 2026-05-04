import CoreBluetooth
import Foundation

@MainActor
final class EmberMugBluetoothCoordinator: NSObject {
    static let maximumSimultaneousMugs = 3

    private enum PushEventID: UInt8 {
        case batteryChanged = 1
        case chargerConnected = 2
        case chargerDisconnected = 3
        case targetTemperatureChanged = 4
        case currentTemperatureChanged = 5
        case liquidLevelChanged = 7
        case activityChanged = 8
    }

    private enum LiquidStateID: UInt8 {
        case adjustingHeater = 0
        case empty = 1
        case filling = 2
        case cooling = 4
        case heating = 5
        case holding = 6
        case coolingWithoutTarget = 7

        var description: String {
            switch self {
            case .adjustingHeater:
                "Adjusting heat"
            case .empty:
                "Empty"
            case .filling:
                "Filling"
            case .cooling:
                "Cooling"
            case .heating:
                "Heating"
            case .holding:
                "Holding temperature"
            case .coolingWithoutTarget:
                "Cooling"
            }
        }

        var impliesEmpty: Bool {
            switch self {
            case .empty:
                true
            case .adjustingHeater, .filling, .cooling, .heating, .holding, .coolingWithoutTarget:
                false
            }
        }
    }

    private struct CandidateRecord {
        let peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var finish: EmberMugFinish?
        var size: EmberMugSize?
    }

    private enum RefreshTrigger {
        case manual
        case automatic
        case postWrite
    }

    private enum ScanMode {
        case autoConnect(Set<UUID>)
        case preferred(UUID)
        case discovery(excluding: Set<UUID>)
        case manual

        func allows(_ identifier: UUID) -> Bool {
            switch self {
            case let .autoConnect(identifiers):
                identifiers.contains(identifier)
            case let .preferred(identifierToFind):
                identifier == identifierToFind
            case let .discovery(excludedIdentifiers):
                !excludedIdentifiers.contains(identifier)
            case .manual:
                true
            }
        }

        var isContinuousDiscovery: Bool {
            if case .discovery = self {
                return true
            }
            return false
        }
    }

    private static let scanTimeout: TimeInterval = 20
    private static let scanProgressDelay: TimeInterval = 12
    private static let connectionTimeout: TimeInterval = 15

    private let onSnapshot: (BluetoothRuntimeSnapshot) -> Void

    private var central: CBCentralManager?
    private var preferredPeripheralIdentifier: UUID?
    private var autoConnectPeripheralIdentifiers: Set<UUID>
    private var sessionsByIdentifier: [UUID: MugPeripheralSession] = [:]
    private var discoveredCandidates: [UUID: CandidateRecord] = [:]
    private var activeScanMode: ScanMode?
    private var scanProgressUpdateWorkItem: DispatchWorkItem?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var autoConnectWorkItem: DispatchWorkItem?
    private var globalDiscoveryPhase: BluetoothRuntimeSnapshot.DiscoveryPhase = .starting
    private var globalDetailMessage = "Checking Bluetooth availability on this Mac."

    init(
        preferredPeripheralIdentifier: String? = nil,
        autoConnectPeripheralIdentifiers: [String] = [],
        onSnapshot: @escaping (BluetoothRuntimeSnapshot) -> Void
    ) {
        self.onSnapshot = onSnapshot
        self.preferredPeripheralIdentifier = preferredPeripheralIdentifier.flatMap(UUID.init(uuidString:))
        let autoConnectIdentifiers = Set(autoConnectPeripheralIdentifiers.compactMap(UUID.init(uuidString:)))
        self.autoConnectPeripheralIdentifiers = Set(autoConnectIdentifiers.prefix(Self.maximumSimultaneousMugs))
        super.init()
        publishGlobalSnapshot()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func setPreferredPeripheralIdentifier(_ identifier: String?) {
        preferredPeripheralIdentifier = identifier.flatMap(UUID.init(uuidString:))
    }

    func setAutoConnectPeripheralIdentifiers(_ identifiers: [String]) {
        autoConnectPeripheralIdentifiers = Set(
            identifiers
                .prefix(Self.maximumSimultaneousMugs)
                .compactMap(UUID.init(uuidString:))
        )
    }

    func connectToCandidate(identifier: String) {
        guard let uuid = UUID(uuidString: identifier), let candidate = discoveredCandidates[uuid] else {
            globalDetailMessage = "That mug is no longer available. Try scanning again."
            AppLog.bluetooth.error("Explicit connect requested for unknown candidate \(identifier, privacy: .public).")
            publishGlobalSnapshot()
            return
        }

        preferredPeripheralIdentifier = uuid
        connect(candidate.peripheral, name: candidate.name, finish: candidate.finish, size: candidate.size)
    }

    func retryScan() {
        guard activeConnectionCount < Self.maximumSimultaneousMugs else {
            globalDiscoveryPhase = .idle
            globalDetailMessage = "Swiftea already has 3 mugs connected or connecting."
            publishGlobalSnapshot()
            return
        }

        startScan(mode: .manual)
    }

    func scanForPreferredMug() {
        guard let preferredPeripheralIdentifier else {
            globalDiscoveryPhase = .idle
            globalDetailMessage = "No saved mug is selected. Use the + button when you want to connect one."
            publishGlobalSnapshot()
            return
        }

        guard !isConnectedOrConnecting(preferredPeripheralIdentifier) else {
            publishSnapshot(for: sessionsByIdentifier[preferredPeripheralIdentifier])
            return
        }

        startScan(mode: .preferred(preferredPeripheralIdentifier))
    }

    func startDiscoveryScan(excluding identifiers: [String]) {
        guard activeConnectionCount < Self.maximumSimultaneousMugs else {
            globalDiscoveryPhase = .idle
            globalDetailMessage = "Swiftea already has 3 mugs connected or connecting."
            publishGlobalSnapshot()
            return
        }

        let excludedIdentifiers = Set(identifiers.compactMap(UUID.init(uuidString:)))
        startScan(mode: .discovery(excluding: excludedIdentifiers))
    }

    func stopDiscoveryScan() {
        guard case .discovery = activeScanMode else { return }

        central?.stopScan()
        cancelScanProgressUpdate()
        cancelScanTimeout()
        cancelAutoConnect()
        discoveredCandidates = [:]
        activeScanMode = nil
        globalDiscoveryPhase = .idle
        globalDetailMessage = "Discovery stopped."
        publishGlobalSnapshot()
    }

    func disconnectMug(identifier: String) {
        guard let uuid = UUID(uuidString: identifier), let session = sessionsByIdentifier[uuid] else {
            globalDetailMessage = "That mug is not connected right now."
            publishGlobalSnapshot()
            return
        }

        session.cancelConnectionTimeout()
        session.resetLiveReadState(keepConnectionState: false)
        session.phase = .disconnected
        session.detailMessage = "Disconnected from \(session.name)."

        if session.peripheral.state == .connected || session.peripheral.state == .connecting {
            central?.cancelPeripheralConnection(session.peripheral)
        }

        publishSnapshot(for: session)
    }

    func forgetMug(identifier: String) {
        guard let uuid = UUID(uuidString: identifier) else { return }

        autoConnectPeripheralIdentifiers.remove(uuid)
        discoveredCandidates.removeValue(forKey: uuid)

        if preferredPeripheralIdentifier == uuid {
            preferredPeripheralIdentifier = nil
        }

        if let session = sessionsByIdentifier[uuid] {
            session.cancelConnectionTimeout()
            session.resetLiveReadState(keepConnectionState: false)

            if session.peripheral.state == .connected || session.peripheral.state == .connecting {
                central?.cancelPeripheralConnection(session.peripheral)
            }

            sessionsByIdentifier.removeValue(forKey: uuid)
        }

        publishGlobalSnapshot()
    }

    func refreshReadings() {
        for session in sessionsByIdentifier.values where session.phase == .connected {
            refreshReadings(for: session.identifier.uuidString, trigger: .manual)
        }
    }

    func refreshReadings(for identifier: String?) {
        refreshReadings(for: identifier, trigger: .manual)
    }

    func setTargetTemperature(_ celsius: Double?) {
        setTargetTemperature(celsius, for: preferredPeripheralIdentifier?.uuidString)
    }

    func setTargetTemperature(_ celsius: Double?, for identifier: String?) {
        guard let session = session(for: identifier) else {
            globalDetailMessage = "Target temperature control is not ready yet."
            AppLog.bluetooth.error("Target temperature write requested without an active mug session.")
            publishGlobalSnapshot()
            return
        }

        guard let targetTemperatureCharacteristic = session.targetTemperatureCharacteristic else {
            session.detailMessage = "Target temperature control is not ready yet."
            AppLog.bluetooth.error("Target temperature write requested before writable characteristic was ready.")
            publishSnapshot(for: session)
            return
        }

        let clampedCelsius = celsius.map { min(max($0, 50.0), 62.0) }
        let rawValue = UInt16((clampedCelsius ?? 0) * 100).littleEndian
        let payload = withUnsafeBytes(of: rawValue) { Data($0) }
        let writeType: CBCharacteristicWriteType = targetTemperatureCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse

        session.hasPendingTargetWrite = true
        session.pendingTargetWriteCelsius = clampedCelsius

        if let clampedCelsius {
            let targetLabel = Self.targetTemperatureLabel(for: clampedCelsius)
            session.detailMessage = "Sending a new target temperature of \(targetLabel) °C."
            AppLog.bluetooth.info("Writing target temperature \(clampedCelsius, format: .fixed(precision: 1)) C to mug \(session.identifier.uuidString, privacy: .public).")
        } else {
            session.detailMessage = "Turning temperature control off."
            AppLog.bluetooth.info("Writing a zero target temperature to turn heating off for mug \(session.identifier.uuidString, privacy: .public).")
        }

        publishSnapshot(for: session)
        session.peripheral.writeValue(payload, for: targetTemperatureCharacteristic, type: writeType)

        if writeType == .withoutResponse {
            session.targetTemperatureCelsius = clampedCelsius ?? 0
            session.lastTargetWriteAt = Date()
            session.hasPendingTargetWrite = false
            session.pendingTargetWriteCelsius = nil
            session.detailMessage = clampedCelsius == nil ? "Temperature control turned off." : "Target temperature updated."
            publishSnapshot(for: session)
            schedulePostWriteRefresh(for: session)
        }
    }

    private var isScanAllowed: Bool {
        switch CBCentralManager.authorization {
        case .allowedAlways, .notDetermined:
            true
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private var activeConnectionCount: Int {
        sessionsByIdentifier.values.filter { session in
            session.phase == .connected || session.phase == .connecting
        }.count
    }

    private func isConnectedOrConnecting(_ identifier: UUID) -> Bool {
        guard let session = sessionsByIdentifier[identifier] else { return false }
        return session.phase == .connected || session.phase == .connecting
    }

    private func session(for identifier: String?) -> MugPeripheralSession? {
        if let identifier, let uuid = UUID(uuidString: identifier) {
            return sessionsByIdentifier[uuid]
        }

        if let preferredPeripheralIdentifier, let session = sessionsByIdentifier[preferredPeripheralIdentifier] {
            return session
        }

        return sessionsByIdentifier.values.first { $0.phase == .connected }
    }

    private func startScan(mode: ScanMode) {
        guard let central else {
            globalDetailMessage = "Bluetooth is still initializing."
            AppLog.bluetooth.notice("Retry requested before Bluetooth finished initializing.")
            publishGlobalSnapshot()
            return
        }

        guard isScanAllowed else {
            globalDetailMessage = "Bluetooth access is required before Swiftea can look for your mug."
            AppLog.bluetooth.error("Scan blocked because Bluetooth access is not allowed.")
            publishGlobalSnapshot()
            return
        }

        guard central.state == .poweredOn else {
            globalDetailMessage = "Turn Bluetooth on and then try scanning again."
            AppLog.bluetooth.notice("Scan blocked because Bluetooth hardware is not powered on.")
            publishGlobalSnapshot()
            return
        }

        cancelScanProgressUpdate()
        cancelScanTimeout()
        cancelAutoConnect()

        if central.isScanning {
            central.stopScan()
        }

        discoveredCandidates = [:]
        activeScanMode = mode
        globalDiscoveryPhase = .scanning
        globalDetailMessage = switch mode {
        case .autoConnect, .preferred:
            "Looking for your saved Ember Mug 2."
        case .discovery:
            "Looking for nearby Ember mugs."
        case .manual:
            "Looking for your Ember Mug 2."
        }

        AppLog.bluetooth.info("Starting Ember scan.")
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        if !mode.isContinuousDiscovery {
            scheduleScanProgressUpdate()
            scheduleScanTimeout()
        }
        publishGlobalSnapshot()
    }

    private func connect(
        _ peripheral: CBPeripheral,
        name: String? = nil,
        finish: EmberMugFinish? = nil,
        size: EmberMugSize? = nil
    ) {
        if sessionsByIdentifier[peripheral.identifier] == nil, activeConnectionCount >= Self.maximumSimultaneousMugs {
            globalDiscoveryPhase = .idle
            globalDetailMessage = "Swiftea already has 3 mugs connected or connecting."
            publishGlobalSnapshot()
            return
        }

        cancelAutoConnect()
        cancelScanProgressUpdate()
        cancelScanTimeout()
        central?.stopScan()
        activeScanMode = nil

        let session = sessionsByIdentifier[peripheral.identifier] ?? MugPeripheralSession(
            peripheral: peripheral,
            name: name ?? peripheral.name ?? "Ember Mug 2",
            finish: finish,
            size: size,
            phase: .connecting,
            detailMessage: "Found \(name ?? peripheral.name ?? "your mug"). Connecting now."
        )

        session.peripheral = peripheral
        session.name = name ?? peripheral.name ?? session.name
        session.finish = finish ?? session.finish
        session.size = size ?? session.size
        session.phase = .connecting
        session.detailMessage = "Found \(session.name). Connecting now."
        sessionsByIdentifier[peripheral.identifier] = session

        AppLog.bluetooth.info(
            "Discovered mug \(session.name, privacy: .public) with finish \(session.finish?.rawValue ?? "unknown", privacy: .public) and size \(session.size?.rawValue ?? "unknown", privacy: .public). Attempting connection."
        )

        central?.connect(peripheral)
        scheduleConnectionTimeout(for: session)
        publishSnapshot(for: session)
    }

    private func recoverExistingConnectionsAndAutoConnectIfPossible() {
        guard let central, central.state == .poweredOn else { return }

        let connectedPeripherals = central.retrieveConnectedPeripherals(withServices: [EmberGATT.service])
        for peripheral in connectedPeripherals where autoConnectPeripheralIdentifiers.contains(peripheral.identifier) {
            guard activeConnectionCount < Self.maximumSimultaneousMugs else { break }
            AppLog.bluetooth.info("Recovered already-connected Ember peripheral from Core Bluetooth.")
            let session = sessionsByIdentifier[peripheral.identifier] ?? MugPeripheralSession(
                peripheral: peripheral,
                name: peripheral.name ?? "Ember Mug 2",
                finish: nil,
                size: nil,
                phase: .connecting,
                detailMessage: "Recovered an existing connection to \(peripheral.name ?? "your mug"). Reading live mug data."
            )
            session.peripheral = peripheral
            session.phase = .connecting
            session.lastConnectedAt = Date()
            session.detailMessage = "Recovered an existing connection to \(session.name). Reading live mug data."
            sessionsByIdentifier[peripheral.identifier] = session
            peripheral.delegate = self
            peripheral.discoverServices([EmberGATT.service])
            session.cancelConnectionTimeout()
            scheduleConnectionTimeout(for: session)
            publishSnapshot(for: session)
        }

        continueAutoConnectScanIfNeeded()
    }

    private func continueAutoConnectScanIfNeeded() {
        let remainingIdentifiers = autoConnectPeripheralIdentifiers
            .filter { !isConnectedOrConnecting($0) }

        guard !remainingIdentifiers.isEmpty else {
            if sessionsByIdentifier.isEmpty {
                globalDiscoveryPhase = .idle
                globalDetailMessage = "No saved mug is selected. Use the + button when you want to connect one."
                publishGlobalSnapshot()
            }
            return
        }

        guard activeConnectionCount < Self.maximumSimultaneousMugs else { return }
        startScan(mode: .autoConnect(remainingIdentifiers))
    }

    private func scheduleScanProgressUpdate() {
        cancelScanProgressUpdate()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.globalDiscoveryPhase == .scanning else { return }

            self.globalDetailMessage = switch self.activeScanMode {
            case .autoConnect, .preferred:
                "Still looking for your saved Ember Mug 2. Keep it nearby, wake it up, or place it on the charger if it stays hidden."
            case .discovery:
                "Still looking for nearby Ember mugs."
            case .manual, nil:
                "Still looking for your Ember Mug 2. Keep it nearby, wake it up, or place it on the charger if it stays hidden."
            }
            AppLog.bluetooth.notice("Scan is still running without an Ember discovery after the initial delay.")
            self.publishGlobalSnapshot()
        }

        scanProgressUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanProgressDelay, execute: workItem)
    }

    private func cancelScanProgressUpdate() {
        scanProgressUpdateWorkItem?.cancel()
        scanProgressUpdateWorkItem = nil
    }

    private func scheduleScanTimeout() {
        cancelScanTimeout()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.globalDiscoveryPhase == .scanning else { return }

            self.central?.stopScan()
            self.cancelAutoConnect()
            self.cancelScanProgressUpdate()

            let scanMode = self.activeScanMode
            self.activeScanMode = nil
            self.globalDiscoveryPhase = .disconnected
            self.globalDetailMessage = switch scanMode {
            case .autoConnect, .preferred:
                "Saved mug was not found. Use the + button if you want to scan again."
            case .discovery:
                "Discovery stopped."
            case .manual, nil:
                self.discoveredCandidates.isEmpty
                    ? "No Ember mug was found. Use the + button to try again."
                    : "Multiple Ember mugs were found. Move the mug you want closer, then use the + button again."
            }

            AppLog.bluetooth.notice("Ember scan timed out.")
            self.publishGlobalSnapshot()
        }

        scanTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanTimeout, execute: workItem)
    }

    private func cancelScanTimeout() {
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
    }

    private func scheduleAutoConnect(to candidate: CandidateRecord) {
        cancelAutoConnect()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.globalDiscoveryPhase == .scanning else { return }
            guard self.discoveredCandidates.count == 1 else { return }

            self.globalDetailMessage = "Found one Ember mug nearby. Connecting now."
            AppLog.bluetooth.info("Auto-connecting to the only discovered Ember candidate.")
            self.connect(candidate.peripheral, name: candidate.name, finish: candidate.finish, size: candidate.size)
        }

        autoConnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func cancelAutoConnect() {
        autoConnectWorkItem?.cancel()
        autoConnectWorkItem = nil
    }

    private func scheduleConnectionTimeout(for session: MugPeripheralSession) {
        session.cancelConnectionTimeout()

        let workItem = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session else { return }
            guard session.phase == .connecting else { return }

            AppLog.bluetooth.error("Connection attempt timed out for \(session.name, privacy: .public).")
            session.phase = .failed
            session.detailMessage = self.timeoutDetailMessage(for: session)
            self.central?.cancelPeripheralConnection(session.peripheral)
            self.publishSnapshot(for: session)
            self.continueAutoConnectScanIfNeeded()
        }

        session.connectionTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: workItem)
    }

    private func timeoutDetailMessage(for session: MugPeripheralSession) -> String {
        "The mug was found, but the Bluetooth connection timed out for \(session.name). Try again with the mug awake, on its charger, and with the official Ember app closed."
    }

    private func evaluateDiscoveryStateAfterRegisteringCandidate(_ candidate: CandidateRecord) {
        switch activeScanMode {
        case let .autoConnect(identifiers):
            if identifiers.contains(candidate.peripheral.identifier) {
                globalDetailMessage = "Found your saved mug, \(candidate.name). Connecting now."
                publishGlobalSnapshot()
                connect(candidate.peripheral, name: candidate.name, finish: candidate.finish, size: candidate.size)
            }
        case let .preferred(identifier):
            if identifier == candidate.peripheral.identifier {
                globalDetailMessage = "Found your saved mug, \(candidate.name). Connecting now."
                publishGlobalSnapshot()
                connect(candidate.peripheral, name: candidate.name, finish: candidate.finish, size: candidate.size)
            }
        case .discovery:
            globalDiscoveryPhase = .scanning
            globalDetailMessage = discoveredCandidates.count == 1
                ? "Found one nearby Ember mug."
                : "Found \(discoveredCandidates.count) nearby Ember mugs."
            publishGlobalSnapshot()
        case .manual:
            switch discoveredCandidates.count {
            case 0:
                break
            case 1:
                globalDiscoveryPhase = .scanning
                globalDetailMessage = "Found one Ember mug nearby. Waiting a moment in case another mug appears."
                scheduleAutoConnect(to: candidate)
            default:
                cancelAutoConnect()
                cancelScanTimeout()
                activeScanMode = nil
                central?.stopScan()
                globalDiscoveryPhase = .disconnected
                globalDetailMessage = "Multiple Ember mugs were found. Move the mug you want closer, then use the + button again."
            }
            publishGlobalSnapshot()
        case nil:
            break
        }
    }

    private func snapshotDiscoveredMugs() -> [BluetoothRuntimeSnapshot.DiscoveredMug] {
        discoveredCandidates.values
            .map {
                BluetoothRuntimeSnapshot.DiscoveredMug(
                    identifier: $0.peripheral.identifier.uuidString,
                    name: $0.name,
                    rssi: $0.rssi,
                    finish: $0.finish,
                    size: $0.size
                )
            }
            .sorted { lhs, rhs in
                if lhs.rssi == rhs.rssi {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.rssi > rhs.rssi
            }
    }

    private func publishSnapshot(for session: MugPeripheralSession?) {
        guard let session else { return }

        onSnapshot(
            BluetoothRuntimeSnapshot(
                authorization: Self.authorizationStatus(from: CBCentralManager.authorization),
                hardwareState: Self.hardwareState(from: central?.state ?? .unknown),
                discoveryPhase: session.phase,
                activePeripheralIdentifier: session.identifier.uuidString,
                discoveredDeviceName: session.name,
                discoveredDeviceFinish: session.finish,
                discoveredDeviceSize: session.size,
                serialNumber: session.serialNumber,
                discoveredMugs: snapshotDiscoveredMugs(),
                isScanning: central?.isScanning ?? false,
                detailMessage: session.detailMessage,
                currentTemperatureCelsius: session.currentTemperatureCelsius,
                targetTemperatureCelsius: session.targetTemperatureCelsius,
                batteryLevel: session.batteryLevel,
                isCharging: session.isCharging,
                contentsLevelRaw: session.contentsLevelRaw,
                liquidStateDescription: session.liquidStateDescription,
                isEmpty: session.isEmpty,
                canReadCurrentTemperature: session.canReadCurrentTemperature,
                canReadTargetTemperature: session.canReadTargetTemperature,
                canReadBattery: session.canReadBattery,
                canReadContents: session.canReadContents,
                canReadActivity: session.canReadActivity,
                canWriteTargetTemperature: session.canWriteTargetTemperature,
                lastBatteryReadingAt: session.lastBatteryReadingAt,
                lastConnectedAt: session.lastConnectedAt,
                lastReadingAt: session.lastReadingAt,
                lastTargetWriteAt: session.lastTargetWriteAt
            )
        )
    }

    private func publishGlobalSnapshot() {
        onSnapshot(
            BluetoothRuntimeSnapshot(
                authorization: Self.authorizationStatus(from: CBCentralManager.authorization),
                hardwareState: Self.hardwareState(from: central?.state ?? .unknown),
                discoveryPhase: globalDiscoveryPhase,
                activePeripheralIdentifier: nil,
                discoveredDeviceName: nil,
                discoveredDeviceFinish: nil,
                discoveredDeviceSize: nil,
                serialNumber: nil,
                discoveredMugs: snapshotDiscoveredMugs(),
                isScanning: central?.isScanning ?? false,
                detailMessage: globalDetailMessage,
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
                lastBatteryReadingAt: nil,
                lastConnectedAt: nil,
                lastReadingAt: nil,
                lastTargetWriteAt: nil
            )
        )
    }

    private func handle(characteristic: CBCharacteristic, for session: MugPeripheralSession) {
        switch characteristic.uuid {
        case EmberGATT.currentTemperature:
            if let data = characteristic.value, let value = Self.temperature(from: data) {
                session.currentTemperatureCelsius = value
                session.lastReadingAt = Date()
                AppLog.bluetooth.debug("Updated current temperature to \(value, format: .fixed(precision: 1)) C.")
            }
        case EmberGATT.targetTemperature:
            if let data = characteristic.value, let value = Self.temperature(from: data) {
                session.targetTemperatureCelsius = value
                session.lastReadingAt = Date()
                AppLog.bluetooth.debug("Updated target temperature to \(value, format: .fixed(precision: 1)) C.")
            }
        case EmberGATT.contentsLevel:
            if let data = characteristic.value, let level = Self.contentsLevel(from: data) {
                session.contentsLevelRaw = level
                if session.isEmpty == nil {
                    if level <= 11 {
                        session.isEmpty = true
                    } else if level >= 14 {
                        session.isEmpty = false
                    }
                }
                session.lastReadingAt = Date()
                AppLog.bluetooth.debug("Updated contents level to \(level).")
            }
        case EmberGATT.liquidState:
            if let data = characteristic.value, let liquidState = Self.liquidState(from: data) {
                session.liquidStateDescription = liquidState.description
                session.isEmpty = liquidState.impliesEmpty
                session.lastReadingAt = Date()
                AppLog.bluetooth.debug("Updated liquid state to \(liquidState.description, privacy: .public).")
            }
        case EmberGATT.battery:
            if let data = characteristic.value, let parsedBattery = Self.battery(from: data) {
                session.batteryLevel = parsedBattery.level
                session.isCharging = parsedBattery.isCharging
                let readAt = Date()
                session.lastReadingAt = readAt
                session.lastBatteryReadingAt = readAt
                AppLog.bluetooth.debug("Updated battery level to \(parsedBattery.level, format: .fixed(precision: 2)); charging: \(parsedBattery.isCharging).")
            }
        case EmberGATT.serialNumber:
            if let data = characteristic.value, let parsedSerialNumber = Self.serialNumber(from: data) {
                session.serialNumber = parsedSerialNumber
                session.lastReadingAt = Date()
                AppLog.bluetooth.debug("Updated serial number to \(parsedSerialNumber, privacy: .public).")
            }
        case EmberGATT.pushEvent:
            if let data = characteristic.value {
                handlePushEvent(data, from: characteristic, for: session)
            }
        default:
            break
        }
    }

    private func handlePushEvent(_ data: Data, from characteristic: CBCharacteristic, for session: MugPeripheralSession) {
        guard let eventByte = data.first, let event = PushEventID(rawValue: eventByte) else {
            AppLog.bluetooth.debug("Received unknown push event payload: \(data as NSData, privacy: .public)")
            return
        }

        session.lastReadingAt = Date()

        switch event {
        case .batteryChanged:
            AppLog.bluetooth.debug("Push event: battery changed.")
            requestRead(for: session.batteryCharacteristic, session: session)
        case .chargerConnected:
            session.isCharging = true
            AppLog.bluetooth.debug("Push event: charger connected.")
            requestRead(for: session.batteryCharacteristic, session: session)
        case .chargerDisconnected:
            session.isCharging = false
            AppLog.bluetooth.debug("Push event: charger disconnected.")
            requestRead(for: session.batteryCharacteristic, session: session)
        case .targetTemperatureChanged:
            AppLog.bluetooth.debug("Push event: target temperature changed.")
            requestRead(for: session.targetTemperatureCharacteristic, session: session)
        case .currentTemperatureChanged:
            AppLog.bluetooth.debug("Push event: current temperature changed.")
            requestRead(for: session.currentTemperatureCharacteristic, session: session)
        case .liquidLevelChanged:
            AppLog.bluetooth.debug("Push event: contents level changed.")
            requestRead(for: session.contentsCharacteristic, session: session)
        case .activityChanged:
            AppLog.bluetooth.debug("Push event: activity changed.")
            requestRead(for: session.activityCharacteristic, session: session)
        }

        if characteristic.uuid == EmberGATT.pushEvent {
            publishSnapshot(for: session)
        }
    }

    private func requestRead(for characteristic: CBCharacteristic?, session: MugPeripheralSession) {
        guard let characteristic, characteristic.properties.contains(.read) else { return }
        session.peripheral.readValue(for: characteristic)
    }

    private func refreshReadings(for identifier: String?, trigger: RefreshTrigger) {
        guard let session = session(for: identifier), session.phase == .connected else {
            if trigger == .manual {
                globalDetailMessage = "Connect to your mug before refreshing live values."
                AppLog.bluetooth.notice("Manual refresh requested without an active connection.")
                publishGlobalSnapshot()
            }
            return
        }

        let readableCharacteristics = session.readableCharacteristics()

        guard !readableCharacteristics.isEmpty else {
            if trigger == .manual {
                session.detailMessage = "Connected, but the mug has not exposed readable characteristics yet."
                AppLog.bluetooth.notice("Manual refresh requested before readable characteristics were available.")
                publishSnapshot(for: session)
            }
            return
        }

        switch trigger {
        case .manual:
            session.detailMessage = "Refreshing live mug values."
            AppLog.bluetooth.info("Manual refresh requested.")
            publishSnapshot(for: session)
        case .automatic:
            AppLog.bluetooth.debug("Polling readable mug characteristics.")
        case .postWrite:
            AppLog.bluetooth.debug("Refreshing mug values after a target temperature write.")
        }

        for characteristic in readableCharacteristics {
            session.peripheral.readValue(for: characteristic)
        }
    }

    private func register(characteristic: CBCharacteristic, for session: MugPeripheralSession) {
        switch characteristic.uuid {
        case EmberGATT.currentTemperature:
            session.currentTemperatureCharacteristic = characteristic
            session.canReadCurrentTemperature = characteristic.properties.contains(.read)
        case EmberGATT.targetTemperature:
            session.targetTemperatureCharacteristic = characteristic
            session.canReadTargetTemperature = characteristic.properties.contains(.read)
            session.canWriteTargetTemperature = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
        case EmberGATT.contentsLevel:
            session.contentsCharacteristic = characteristic
            session.canReadContents = characteristic.properties.contains(.read)
        case EmberGATT.liquidState:
            session.activityCharacteristic = characteristic
            session.canReadActivity = characteristic.properties.contains(.read)
        case EmberGATT.battery:
            session.batteryCharacteristic = characteristic
            session.canReadBattery = characteristic.properties.contains(.read)
        case EmberGATT.serialNumber:
            session.serialNumberCharacteristic = characteristic
        case EmberGATT.pushEvent:
            session.pushEventCharacteristic = characteristic
        default:
            break
        }
    }

    private func startPollingIfNeeded(for session: MugPeripheralSession) {
        guard session.refreshTimer == nil else { return }
        guard session.phase == .connected else { return }
        guard session.hasReadableCharacteristics else { return }

        let sessionIdentifier = session.identifier.uuidString
        let timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshReadings(for: sessionIdentifier, trigger: .automatic)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        session.refreshTimer = timer
    }

    private func schedulePostWriteRefresh(for session: MugPeripheralSession) {
        let sessionIdentifier = session.identifier.uuidString
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.refreshReadings(for: sessionIdentifier, trigger: .postWrite)
        }
    }

    private static func likelyEmberName(from peripheral: CBPeripheral, advertisementData: [String: Any]) -> String? {
        if let advertisedLocalName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, isLikelyEmberName(advertisedLocalName) {
            return advertisedLocalName
        }

        if let peripheralName = peripheral.name, isLikelyEmberName(peripheralName) {
            return peripheralName
        }

        return nil
    }

    private static func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
        (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    }

    private static func isLikelyEmberAdvertisement(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let advertisedName = likelyEmberName(from: peripheral, advertisementData: advertisementData) {
            return advertisedName.localizedCaseInsensitiveContains("ember")
        }

        return !advertisedServiceUUIDs(from: advertisementData)
            .filter { $0.uuidString.uppercased().hasPrefix("FC54") }
            .isEmpty
    }

    private static func isLikelyEmberName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("ember")
            || name.localizedCaseInsensitiveContains("mug")
    }

    private static func temperature(from data: Data) -> Double? {
        guard data.count >= 2 else { return nil }

        let value = data.withUnsafeBytes { rawBuffer -> UInt16 in
            rawBuffer.load(as: UInt16.self)
        }
        return Double(UInt16(littleEndian: value)) / 100
    }

    private static func battery(from data: Data) -> (level: Double, isCharging: Bool)? {
        guard data.count >= 2 else { return nil }
        let level = Double(data[0]) / 100
        let isCharging = data[1] == 1
        return (level, isCharging)
    }

    private static func contentsLevel(from data: Data) -> Int? {
        guard let firstByte = data.first else { return nil }
        return Int(firstByte)
    }

    private static func liquidState(from data: Data) -> LiquidStateID? {
        guard let firstByte = data.first else { return nil }
        return LiquidStateID(rawValue: firstByte)
    }

    nonisolated static func serialNumber(from data: Data) -> String? {
        guard data.count > 7 else { return nil }

        let serialBytes = data.dropFirst(7)
        guard let decoded = String(data: serialBytes, encoding: .ascii) else { return nil }

        let trimmed = decoded
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }

    private static func authorizationStatus(from authorization: CBManagerAuthorization) -> BluetoothRuntimeSnapshot.AuthorizationStatus {
        switch authorization {
        case .allowedAlways:
            .allowed
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    private static func hardwareState(from state: CBManagerState) -> BluetoothRuntimeSnapshot.HardwareState {
        switch state {
        case .unknown:
            .unknown
        case .resetting:
            .resetting
        case .unsupported:
            .unsupported
        case .unauthorized:
            .unauthorized
        case .poweredOff:
            .poweredOff
        case .poweredOn:
            .poweredOn
        @unknown default:
            .unknown
        }
    }
}

extension EmberMugBluetoothCoordinator: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            globalDiscoveryPhase = .starting
            globalDetailMessage = "Checking Bluetooth availability on this Mac."
            AppLog.bluetooth.notice("Bluetooth state is unknown.")
        case .resetting:
            for session in sessionsByIdentifier.values {
                session.resetLiveReadState(keepConnectionState: false)
                publishSnapshot(for: session)
            }
            globalDiscoveryPhase = .starting
            globalDetailMessage = "Bluetooth is resetting. Swiftea will try again in a moment."
            AppLog.bluetooth.notice("Bluetooth is resetting.")
        case .unsupported:
            for session in sessionsByIdentifier.values {
                session.resetLiveReadState(keepConnectionState: false)
                session.phase = .failed
                session.detailMessage = "This Mac does not support the Bluetooth features Swiftea needs."
                publishSnapshot(for: session)
            }
            globalDiscoveryPhase = .failed
            globalDetailMessage = "This Mac does not support the Bluetooth features Swiftea needs."
            AppLog.bluetooth.error("Bluetooth is unsupported on this Mac.")
        case .unauthorized:
            for session in sessionsByIdentifier.values {
                session.resetLiveReadState(keepConnectionState: false)
                session.phase = .failed
                session.detailMessage = "Bluetooth access is blocked for Swiftea."
                publishSnapshot(for: session)
            }
            globalDiscoveryPhase = .failed
            globalDetailMessage = "Bluetooth access is blocked for Swiftea."
            AppLog.bluetooth.error("Bluetooth is unauthorized at the Core Bluetooth level.")
        case .poweredOff:
            for session in sessionsByIdentifier.values {
                session.resetLiveReadState(keepConnectionState: false)
                session.detailMessage = "Bluetooth is off. Turn it on to find your Ember Mug 2."
                publishSnapshot(for: session)
            }
            globalDiscoveryPhase = .idle
            globalDetailMessage = "Bluetooth is off. Turn it on to find your Ember Mug 2."
            AppLog.bluetooth.notice("Bluetooth hardware is powered off.")
        case .poweredOn:
            globalDetailMessage = "Bluetooth is ready. Swiftea will look for mugs set to reconnect automatically now."
            AppLog.bluetooth.info("Bluetooth hardware is powered on.")
            recoverExistingConnectionsAndAutoConnectIfPossible()
            return
        @unknown default:
            globalDiscoveryPhase = .failed
            globalDetailMessage = "Bluetooth reported an unknown state."
            AppLog.bluetooth.error("Bluetooth entered an unknown state.")
        }

        publishGlobalSnapshot()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard Self.isLikelyEmberAdvertisement(for: peripheral, advertisementData: advertisementData) else {
            return
        }

        if let activeScanMode, !activeScanMode.allows(peripheral.identifier) {
            AppLog.bluetooth.debug("Ignoring non-target Ember candidate during saved-mug scan.")
            return
        }

        guard !isConnectedOrConnecting(peripheral.identifier) else { return }
        guard activeConnectionCount < Self.maximumSimultaneousMugs else { return }

        let advertisedName = Self.likelyEmberName(from: peripheral, advertisementData: advertisementData) ?? peripheral.name ?? "unknown"
        let advertisedFinish = EmberAdvertisementParser.finish(from: advertisementData)
        let advertisedSize = EmberAdvertisementParser.size(from: advertisementData)
        let advertisedServices = Self.advertisedServiceUUIDs(from: advertisementData).map(\.uuidString).joined(separator: ", ")
        AppLog.bluetooth.info(
            "Discovered likely Ember peripheral \(advertisedName, privacy: .public). Finish: \(advertisedFinish?.rawValue ?? "unknown", privacy: .public). Size: \(advertisedSize?.rawValue ?? "unknown", privacy: .public). Services: \(advertisedServices, privacy: .public)"
        )

        let candidate = CandidateRecord(
            peripheral: peripheral,
            name: advertisedName,
            rssi: RSSI.intValue,
            finish: advertisedFinish ?? discoveredCandidates[peripheral.identifier]?.finish,
            size: advertisedSize ?? discoveredCandidates[peripheral.identifier]?.size
        )
        discoveredCandidates[peripheral.identifier] = candidate
        evaluateDiscoveryStateAfterRegisteringCandidate(candidate)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let session = sessionsByIdentifier[peripheral.identifier] ?? MugPeripheralSession(
            peripheral: peripheral,
            name: peripheral.name ?? "Ember Mug 2",
            finish: discoveredCandidates[peripheral.identifier]?.finish,
            size: discoveredCandidates[peripheral.identifier]?.size,
            phase: .connecting,
            detailMessage: "Connected to \(peripheral.name ?? "your mug"). Reading live mug data."
        )
        session.cancelConnectionTimeout()
        session.peripheral = peripheral
        session.phase = .connecting
        session.name = peripheral.name ?? session.name
        session.finish = discoveredCandidates[peripheral.identifier]?.finish ?? session.finish
        session.size = discoveredCandidates[peripheral.identifier]?.size ?? session.size
        session.lastConnectedAt = Date()
        session.detailMessage = "Connected to \(session.name). Reading live mug data."
        sessionsByIdentifier[peripheral.identifier] = session
        AppLog.bluetooth.info("Connected to mug \(session.name, privacy: .public). Discovering services.")
        peripheral.delegate = self
        peripheral.discoverServices([EmberGATT.service])
        scheduleConnectionTimeout(for: session)
        publishSnapshot(for: session)
        continueAutoConnectScanIfNeeded()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        let session = sessionsByIdentifier[peripheral.identifier]
        session?.cancelConnectionTimeout()
        session?.resetLiveReadState(keepConnectionState: false)
        session?.phase = .failed
        session?.detailMessage = "Could not connect to \(peripheral.name ?? "your mug"). Try scanning again."
        if let error {
            AppLog.bluetooth.error("Failed to connect to mug \(peripheral.name ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            AppLog.bluetooth.error("Failed to connect to mug \(peripheral.name ?? "unknown", privacy: .public).")
        }
        publishSnapshot(for: session)
        continueAutoConnectScanIfNeeded()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        let session = sessionsByIdentifier[peripheral.identifier]
        session?.cancelConnectionTimeout()
        session?.resetLiveReadState(keepConnectionState: false)
        session?.phase = .disconnected
        session?.detailMessage = "Connection lost. You can retry the scan whenever you are ready."
        if let error {
            AppLog.bluetooth.notice("Disconnected from mug \(peripheral.name ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            AppLog.bluetooth.notice("Disconnected from mug \(peripheral.name ?? "unknown", privacy: .public).")
        }
        publishSnapshot(for: session)
    }
}

extension EmberMugBluetoothCoordinator: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let session = sessionsByIdentifier[peripheral.identifier] else { return }

        guard error == nil else {
            session.cancelConnectionTimeout()
            session.phase = .failed
            session.detailMessage = "The mug connected, but its Bluetooth services could not be read."
            AppLog.bluetooth.error("Connected mug services could not be discovered.")
            publishSnapshot(for: session)
            return
        }

        AppLog.bluetooth.info("Discovered services for mug \(session.name, privacy: .public).")
        for service in peripheral.services ?? [] where service.uuid == EmberGATT.service {
            peripheral.discoverCharacteristics([
                EmberGATT.currentTemperature,
                EmberGATT.targetTemperature,
                EmberGATT.contentsLevel,
                EmberGATT.liquidState,
                EmberGATT.battery,
                EmberGATT.serialNumber,
                EmberGATT.pushEvent
            ], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard let session = sessionsByIdentifier[peripheral.identifier] else { return }

        guard error == nil else {
            session.cancelConnectionTimeout()
            session.phase = .failed
            session.detailMessage = "Connected, but the mug characteristics could not be loaded."
            AppLog.bluetooth.error("Mug characteristics could not be discovered.")
            publishSnapshot(for: session)
            return
        }

        AppLog.bluetooth.info("Discovered characteristics for Ember service.")
        for characteristic in service.characteristics ?? [] {
            register(characteristic: characteristic, for: session)

            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        startPollingIfNeeded(for: session)
        session.detailMessage = "Connected. Waiting for the first live readings from your mug."
        publishSnapshot(for: session)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let session = sessionsByIdentifier[peripheral.identifier] else { return }

        guard error == nil else {
            session.detailMessage = "Connected, but one of the mug readings failed to update."
            AppLog.bluetooth.error("A mug characteristic value update failed.")
            publishSnapshot(for: session)
            return
        }

        handle(characteristic: characteristic, for: session)
        if session.hasDashboardReading {
            session.cancelConnectionTimeout()
            session.phase = .connected
            startPollingIfNeeded(for: session)
            session.detailMessage = "Connected. Live mug values are updating."
        } else {
            session.detailMessage = "Connected. Waiting for the first live readings from your mug."
        }
        publishSnapshot(for: session)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let session = sessionsByIdentifier[peripheral.identifier] else { return }

        guard error == nil else {
            session.detailMessage = "The mug rejected the target temperature change. Try again after reconnecting."
            AppLog.bluetooth.error("Target temperature write failed.")
            session.hasPendingTargetWrite = false
            session.pendingTargetWriteCelsius = nil
            publishSnapshot(for: session)
            return
        }

        if characteristic.uuid == EmberGATT.targetTemperature {
            if session.hasPendingTargetWrite {
                session.targetTemperatureCelsius = session.pendingTargetWriteCelsius ?? 0
            }

            let didTurnOffTemperatureControl = session.hasPendingTargetWrite && session.pendingTargetWriteCelsius == nil
            session.hasPendingTargetWrite = false
            session.pendingTargetWriteCelsius = nil
            session.lastTargetWriteAt = Date()
            if didTurnOffTemperatureControl {
                session.detailMessage = "Temperature control turned off."
                AppLog.bluetooth.info("Target temperature write succeeded and heating was turned off.")
            } else {
                session.detailMessage = "Target temperature updated."
                AppLog.bluetooth.info("Target temperature write succeeded.")
            }
            refreshReadings(for: session.identifier.uuidString, trigger: .postWrite)
            publishSnapshot(for: session)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            AppLog.bluetooth.error("Notification state update failed for characteristic \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        AppLog.bluetooth.debug("Notification state updated for characteristic \(characteristic.uuid.uuidString, privacy: .public). Notifying: \(characteristic.isNotifying).")
    }

    private static func targetTemperatureLabel(for celsius: Double) -> String {
        celsius.formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}
