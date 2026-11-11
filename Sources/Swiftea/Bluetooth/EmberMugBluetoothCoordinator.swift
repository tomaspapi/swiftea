import CoreBluetooth
import Foundation

struct DiscoveryCandidateCache<Value> {
    private struct Entry {
        let value: Value
        let lastSeenAt: Date
    }

    let maximumCount: Int
    let lifetime: TimeInterval
    private var entries: [UUID: Entry] = [:]

    init(maximumCount: Int = 32, lifetime: TimeInterval = 90) {
        precondition(maximumCount > 0 && lifetime > 0)
        self.maximumCount = maximumCount
        self.lifetime = lifetime
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }
    var values: [Value] { entries.values.map(\.value) }
    subscript(identifier: UUID) -> Value? { entries[identifier]?.value }

    mutating func register(_ value: Value, identifier: UUID, now: Date = Date()) {
        expire(now: now)
        if entries[identifier] == nil, entries.count >= maximumCount {
            let oldest = entries.min { lhs, rhs in
                if lhs.value.lastSeenAt == rhs.value.lastSeenAt {
                    return lhs.key.uuidString < rhs.key.uuidString
                }
                return lhs.value.lastSeenAt < rhs.value.lastSeenAt
            }
            if let oldest { entries.removeValue(forKey: oldest.key) }
        }
        entries[identifier] = Entry(value: value, lastSeenAt: now)
    }

    @discardableResult
    mutating func expire(now: Date = Date()) -> Bool {
        let oldCount = entries.count
        entries = entries.filter { now.timeIntervalSince($0.value.lastSeenAt) < lifetime }
        return entries.count != oldCount
    }

    mutating func removeValue(forKey identifier: UUID) { entries.removeValue(forKey: identifier) }
    mutating func removeAll() { entries.removeAll() }
}

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

        func allowsNameOnlyMatch(for identifier: UUID) -> Bool {
            switch self {
            case let .autoConnect(identifiers):
                identifiers.contains(identifier)
            case let .preferred(identifierToFind):
                identifier == identifierToFind
            case .discovery, .manual:
                false
            }
        }

        var isContinuousDiscovery: Bool {
            if case .discovery = self {
                return true
            }
            return false
        }

        var keepsScanningUntilStopped: Bool {
            switch self {
            case .autoConnect, .discovery:
                true
            case .preferred, .manual:
                false
            }
        }

        var scanServiceFilter: [CBUUID]? {
            switch self {
            case .discovery, .manual:
                EmberAdvertisementParser.discoveryServiceUUIDs
            case .autoConnect, .preferred:
                nil
            }
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
    private var discoveredCandidates = DiscoveryCandidateCache<CandidateRecord>()
    private var publishedDiscoveredMugs: [BluetoothRuntimeSnapshot.DiscoveredMug] = []
    private var discoveryPublicationWorkItem: DispatchWorkItem?
    private var discoveryExpiryWorkItem: DispatchWorkItem?
    private var readingPublicationByMug: [UUID: DispatchWorkItem] = [:]
    private var activeScanMode: ScanMode?
    private var scanProgressUpdateWorkItem: DispatchWorkItem?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var autoConnectWorkItem: DispatchWorkItem?
    private var globalDiscoveryPhase: BluetoothRuntimeSnapshot.DiscoveryPhase = .starting
    private var globalDetailMessage = "Checking Bluetooth availability on this Mac."
    private lazy var connectionMonitor = MugConnectionMonitor { [weak self] in
        self?.maintainConnections()
    }

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
        let updatedIdentifiers = Set(
            identifiers
                .prefix(Self.maximumSimultaneousMugs)
                .compactMap(UUID.init(uuidString:))
        )
        guard updatedIdentifiers != autoConnectPeripheralIdentifiers else { return }

        let removedIdentifiers = autoConnectPeripheralIdentifiers.subtracting(updatedIdentifiers)
        autoConnectPeripheralIdentifiers = updatedIdentifiers

        for identifier in removedIdentifiers {
            guard
                let session = sessionsByIdentifier[identifier],
                session.phase == .connecting,
                session.peripheral.state == .connecting
            else { continue }

            session.cancelConnectionTimeout()
            central?.cancelPeripheralConnection(session.peripheral)
            session.resetLiveReadState(keepConnectionState: false)
            session.phase = .disconnected
            session.detailMessage = "Automatic reconnect is off for \(session.name)."
            publishSnapshot(for: session)
        }

        if case .autoConnect = activeScanMode {
            central?.stopScan()
            cancelScanProgressUpdate()
            cancelScanTimeout()
            activeScanMode = nil
            continueAutoConnectScanIfNeeded()
        }
        synchronizeConnectionMonitoring()
    }

    func recoverAutoConnectMugs() {
        maintainConnections()
    }

    private func synchronizeConnectionMonitoring() {
        let needsMonitoring = !autoConnectPeripheralIdentifiers.isEmpty
            || sessionsByIdentifier.values.contains { $0.phase == .connected || $0.phase == .connecting }
        connectionMonitor.setEnabled(needsMonitoring && central?.state == .poweredOn && isScanAllowed)
    }

    private func maintainConnections() {
        guard let central, central.state == .poweredOn, isScanAllowed else { return }

        for session in Array(sessionsByIdentifier.values) {
            let mayReconnect = autoConnectPeripheralIdentifiers.contains(session.identifier)
            switch Self.maintenanceAction(
                phase: session.phase,
                peripheralState: session.peripheral.state,
                mayReconnect: mayReconnect,
                hasReadableCharacteristics: session.hasReadableCharacteristics,
                hasSetupDeadline: session.connectionTimeoutWorkItem != nil
            ) {
            case .markDisconnected:
                session.cancelConnectionTimeout()
                session.resetLiveReadState(keepConnectionState: false)
                session.detailMessage = "Waiting for the mug to become available."
                publishSnapshot(for: session)
            case .wait:
                // Native pending requests must survive an overnight absence, not time out in a loop.
                continue
            case .discoverServices:
                session.resetLiveReadState(keepConnectionState: false)
                session.phase = .connecting
                session.peripheral.delegate = self
                session.peripheral.discoverServices([EmberGATT.service])
                scheduleConnectionTimeout(for: session)
                publishSnapshot(for: session)
            case .read:
                var requiredCharacteristics: [CBUUID] = []
                if session.canReadCurrentTemperature { requiredCharacteristics.append(EmberGATT.currentTemperature) }
                if session.canReadActivity {
                    requiredCharacteristics.append(EmberGATT.liquidState)
                } else if session.canReadContents {
                    requiredCharacteristics.append(EmberGATT.contentsLevel)
                }
                let action = session.readingHealth.action(
                    requiredCharacteristics: requiredCharacteristics,
                    uptime: ProcessInfo.processInfo.systemUptime
                )
                if action == .reconnect, mayReconnect {
                    AppLog.bluetooth.notice("Replacing an unresponsive saved-mug connection after a fresh-read attempt.")
                    session.cancelConnectionTimeout()
                    session.resetLiveReadState(keepConnectionState: false)
                    session.phase = .connecting
                    session.detailMessage = "Restoring live mug readings."
                    central.cancelPeripheralConnection(session.peripheral)
                    publishSnapshot(for: session)
                } else {
                    refreshReadings(for: session.identifier.uuidString, trigger: .automatic)
                }
            }
        }

        recoverExistingConnectionsAndAutoConnectIfPossible()
        synchronizeConnectionMonitoring()
    }

    enum MaintenanceAction: Equatable {
        case wait
        case markDisconnected
        case discoverServices
        case read
    }

    nonisolated static func maintenanceAction(
        phase: BluetoothRuntimeSnapshot.DiscoveryPhase,
        peripheralState: CBPeripheralState,
        mayReconnect: Bool,
        hasReadableCharacteristics: Bool,
        hasSetupDeadline: Bool
    ) -> MaintenanceAction {
        guard mayReconnect || phase == .connected || phase == .connecting else { return .wait }
        switch peripheralState {
        case .disconnected:
            return phase == .connected || phase == .connecting ? .markDisconnected : .wait
        case .connecting, .disconnecting:
            return .wait
        case .connected:
            if phase == .connected, hasReadableCharacteristics { return .read }
            return hasSetupDeadline ? .wait : .discoverServices
        @unknown default:
            return .wait
        }
    }

    func connectToCandidate(identifier: String) {
        discoveredCandidates.expire()
        guard let uuid = UUID(uuidString: identifier), let candidate = discoveredCandidates[uuid] else {
            globalDetailMessage = "That mug is no longer available. Try scanning again."
            AppLog.bluetooth.error("Explicit connect requested for unknown candidate \(identifier, privacy: .private).")
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
        clearDiscoveryCandidates()
        activeScanMode = nil
        globalDiscoveryPhase = .idle
        globalDetailMessage = "Discovery stopped."
        publishGlobalSnapshot()
        continueAutoConnectScanIfNeeded()
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

        readingPublicationByMug.removeValue(forKey: uuid)?.cancel()
        autoConnectPeripheralIdentifiers.remove(uuid)
        discoveredCandidates.removeValue(forKey: uuid)
        refreshDiscoveredMugsSnapshot()

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
            AppLog.bluetooth.info("Writing target temperature \(clampedCelsius, format: .fixed(precision: 1)) C to mug \(session.identifier.uuidString, privacy: .private).")
        } else {
            session.detailMessage = "Turning temperature control off."
            AppLog.bluetooth.info("Writing a zero target temperature to turn heating off for mug \(session.identifier.uuidString, privacy: .private).")
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

        clearDiscoveryCandidates()
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
        central.scanForPeripherals(withServices: mode.scanServiceFilter, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: mode.isContinuousDiscovery
        ])
        if !mode.isContinuousDiscovery {
            scheduleScanProgressUpdate()
        }
        if !mode.keepsScanningUntilStopped {
            scheduleScanTimeout()
        }
        if mode.isContinuousDiscovery {
            scheduleDiscoveryExpiry()
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
        clearDiscoveryCandidates()

        AppLog.bluetooth.info(
            "Discovered mug \(session.name, privacy: .private) with finish \(session.finish?.rawValue ?? "unknown", privacy: .private) and size \(session.size?.rawValue ?? "unknown", privacy: .private). Attempting connection."
        )

        central?.connect(
            peripheral,
            options: connectionOptions(for: peripheral.identifier)
        )
        scheduleConnectionTimeout(for: session)
        publishSnapshot(for: session)
    }

    private func connectionOptions(for identifier: UUID) -> [String: Any]? {
        guard autoConnectPeripheralIdentifiers.contains(identifier) else { return nil }
        return [CBConnectPeripheralOptionEnableAutoReconnect: true]
    }

    private func beginPersistentAutoConnect(to peripheral: CBPeripheral) {
        guard autoConnectPeripheralIdentifiers.contains(peripheral.identifier) else { return }
        guard !isConnectedOrConnecting(peripheral.identifier) else { return }
        guard activeConnectionCount < Self.maximumSimultaneousMugs else { return }

        let session = sessionsByIdentifier[peripheral.identifier] ?? MugPeripheralSession(
            peripheral: peripheral,
            name: peripheral.name ?? "Ember Mug 2",
            finish: nil,
            size: nil,
            phase: .connecting,
            detailMessage: "Waiting for \(peripheral.name ?? "your mug") to become available."
        )

        session.cancelConnectionTimeout()
        session.peripheral = peripheral
        session.name = peripheral.name ?? session.name
        session.resetLiveReadState(keepConnectionState: false)
        session.phase = .connecting
        session.detailMessage = "Waiting for \(session.name) to become available."
        sessionsByIdentifier[peripheral.identifier] = session
        peripheral.delegate = self

        AppLog.bluetooth.info("Keeping a native reconnect request pending for saved mug \(session.name, privacy: .private).")
        central?.connect(
            peripheral,
            options: [CBConnectPeripheralOptionEnableAutoReconnect: true]
        )
        publishSnapshot(for: session)
    }

    private func recoverExistingConnectionsAndAutoConnectIfPossible() {
        guard let central, central.state == .poweredOn else { return }

        let connectedPeripherals = central.retrieveConnectedPeripherals(withServices: [EmberGATT.service])
        for peripheral in connectedPeripherals where autoConnectPeripheralIdentifiers.contains(peripheral.identifier) {
            guard !isConnectedOrConnecting(peripheral.identifier) else { continue }
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

        let identifiersNeedingConnection = autoConnectPeripheralIdentifiers.filter {
            !isConnectedOrConnecting($0)
        }
        let knownPeripherals = central.retrievePeripherals(
            withIdentifiers: Array(identifiersNeedingConnection)
        )
        for peripheral in knownPeripherals {
            beginPersistentAutoConnect(to: peripheral)
        }

        continueAutoConnectScanIfNeeded()
    }

    private func continueAutoConnectScanIfNeeded() {
        let remainingIdentifiers = autoConnectPeripheralIdentifiers
            .filter { !isConnectedOrConnecting($0) }

        guard !remainingIdentifiers.isEmpty else {
            if case .autoConnect = activeScanMode {
                central?.stopScan()
                cancelScanProgressUpdate()
                cancelScanTimeout()
                activeScanMode = nil
            }
            if sessionsByIdentifier.isEmpty {
                globalDiscoveryPhase = .idle
                globalDetailMessage = "No saved mug is selected. Use the + button when you want to connect one."
                publishGlobalSnapshot()
            }
            return
        }

        guard activeConnectionCount < Self.maximumSimultaneousMugs else { return }
        if let activeScanMode {
            switch activeScanMode {
            case .discovery, .manual, .preferred:
                return
            case .autoConnect:
                break
            }
        }
        if case let .autoConnect(identifiers) = activeScanMode,
           identifiers == remainingIdentifiers, central?.isScanning == true { return }
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

            AppLog.bluetooth.error("Connection attempt timed out for \(session.name, privacy: .private).")
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
        if activeScanMode?.isContinuousDiscovery != true {
            refreshDiscoveredMugsSnapshot()
        }
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
            scheduleDiscoveryPublication()
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
        publishedDiscoveredMugs
    }

    private func refreshDiscoveredMugsSnapshot() {
        discoveredCandidates.expire()
        publishedDiscoveredMugs = discoveredCandidates.values
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
                    if lhs.name == rhs.name { return lhs.identifier < rhs.identifier }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.rssi > rhs.rssi
            }
    }

    private func scheduleDiscoveryPublication() {
        guard discoveryPublicationWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeScanMode?.isContinuousDiscovery == true else { return }
            self.discoveryPublicationWorkItem = nil
            self.refreshDiscoveredMugsSnapshot()
            self.globalDetailMessage = self.discoveredCandidates.count == 1
                ? "Found one nearby Ember mug."
                : "Found \(self.discoveredCandidates.count) nearby Ember mugs."
            self.publishGlobalSnapshot()
        }
        discoveryPublicationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func scheduleDiscoveryExpiry() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeScanMode?.isContinuousDiscovery == true else { return }
            self.discoveryExpiryWorkItem = nil
            if self.discoveredCandidates.expire() {
                self.scheduleDiscoveryPublication()
            }
            self.scheduleDiscoveryExpiry()
        }
        discoveryExpiryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
    }

    private func clearDiscoveryCandidates() {
        discoveryPublicationWorkItem?.cancel()
        discoveryPublicationWorkItem = nil
        discoveryExpiryWorkItem?.cancel()
        discoveryExpiryWorkItem = nil
        discoveredCandidates.removeAll()
        publishedDiscoveredMugs = []
    }

    private func publishSnapshot(for session: MugPeripheralSession?, coalescingReadings: Bool = false) {
        guard let session else { return }
        synchronizeConnectionMonitoring()

        if coalescingReadings {
            guard readingPublicationByMug[session.identifier] == nil else { return }
            let workItem = DispatchWorkItem { [weak self, weak session] in
                guard let self, let session, self.sessionsByIdentifier[session.identifier] === session else { return }
                self.readingPublicationByMug[session.identifier] = nil
                self.publishSnapshot(for: session)
            }
            readingPublicationByMug[session.identifier] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
            return
        }
        readingPublicationByMug.removeValue(forKey: session.identifier)?.cancel()

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
        synchronizeConnectionMonitoring()
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
                session.readingHealth.record(characteristic.uuid)
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
                session.readingHealth.record(characteristic.uuid)
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
                session.readingHealth.record(characteristic.uuid)
                session.isEmpty = liquidState.impliesEmpty
                session.lastReadingAt = Date()
                AppLog.bluetooth.debug("Updated liquid state to \(liquidState.description, privacy: .private).")
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
                AppLog.bluetooth.debug("Updated serial number to \(parsedSerialNumber, privacy: .private).")
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
            AppLog.bluetooth.debug("Received unknown push event payload: \(data as NSData, privacy: .private)")
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
            publishSnapshot(for: session, coalescingReadings: true)
        }
    }

    private func requestRead(for characteristic: CBCharacteristic?, session: MugPeripheralSession) {
        guard let characteristic, characteristic.properties.contains(.read) else { return }
        guard session.pushReadBudget.admit(characteristic.uuid, uptime: ProcessInfo.processInfo.systemUptime) else { return }
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

    private func schedulePostWriteRefresh(for session: MugPeripheralSession) {
        let sessionIdentifier = session.identifier.uuidString
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.refreshReadings(for: sessionIdentifier, trigger: .postWrite)
        }
    }

    private static func likelyEmberName(from peripheral: CBPeripheral, advertisementData: [String: Any]) -> String? {
        EmberAdvertisementParser.likelyName(from: advertisementData, peripheralName: peripheral.name)
    }

    private static func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
        EmberAdvertisementParser.serviceUUIDs(from: advertisementData)
    }

    nonisolated static func shouldRegisterDiscoveredCandidate(
        trust: EmberAdvertisementTrust,
        isSavedTarget: Bool
    ) -> Bool {
        switch trust {
        case .serviceBacked:
            true
        case .nameOnly:
            isSavedTarget
        case .unrelated:
            false
        }
    }

    nonisolated static func temperature(from data: Data) -> Double? {
        guard data.count >= 2 else { return nil }

        let rawValue = UInt16(data[0]) | (UInt16(data[1]) << 8)
        return Double(rawValue) / 100
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
        if central.state != .poweredOn {
            clearDiscoveryCandidates()
            activeScanMode = nil
        }
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
            maintainConnections()
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
        guard let activeScanMode else { return }
        let trust = EmberAdvertisementParser.trust(from: advertisementData, peripheralName: peripheral.name)
        let isSavedTarget = activeScanMode.allowsNameOnlyMatch(for: peripheral.identifier)

        guard Self.shouldRegisterDiscoveredCandidate(trust: trust, isSavedTarget: isSavedTarget) else {
            if trust == .nameOnly {
                AppLog.bluetooth.debug("Ignoring name-only Ember candidate without service-backed advertisement evidence.")
            }
            return
        }

        if !activeScanMode.allows(peripheral.identifier) {
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
            "Discovered likely Ember peripheral \(advertisedName, privacy: .private). Finish: \(advertisedFinish?.rawValue ?? "unknown", privacy: .private). Size: \(advertisedSize?.rawValue ?? "unknown", privacy: .private). Services: \(advertisedServices, privacy: .private)"
        )

        let candidate = CandidateRecord(
            peripheral: peripheral,
            name: advertisedName,
            rssi: RSSI.intValue,
            finish: advertisedFinish ?? discoveredCandidates[peripheral.identifier]?.finish,
            size: advertisedSize ?? discoveredCandidates[peripheral.identifier]?.size
        )
        discoveredCandidates.register(candidate, identifier: peripheral.identifier)
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
        session.readingHealth = MugReadingHealth()
        session.detailMessage = "Connected to \(session.name). Reading live mug data."
        sessionsByIdentifier[peripheral.identifier] = session
        AppLog.bluetooth.info("Connected to mug \(session.name, privacy: .private). Discovering services.")
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
            AppLog.bluetooth.error("Failed to connect to mug \(peripheral.name ?? "unknown", privacy: .private): \(error.localizedDescription, privacy: .private)")
        } else {
            AppLog.bluetooth.error("Failed to connect to mug \(peripheral.name ?? "unknown", privacy: .private).")
        }
        publishSnapshot(for: session)
        continueAutoConnectScanIfNeeded()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        handleDisconnect(
            peripheral,
            isReconnecting: false,
            error: error
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: (any Error)?
    ) {
        handleDisconnect(
            peripheral,
            isReconnecting: isReconnecting,
            error: error
        )
    }

    private func handleDisconnect(
        _ peripheral: CBPeripheral,
        isReconnecting: Bool,
        error: (any Error)?
    ) {
        let session = sessionsByIdentifier[peripheral.identifier]
        session?.cancelConnectionTimeout()
        session?.resetLiveReadState(keepConnectionState: false)
        let shouldKeepReconnecting = isReconnecting
            && autoConnectPeripheralIdentifiers.contains(peripheral.identifier)

        if isReconnecting, !shouldKeepReconnecting {
            central?.cancelPeripheralConnection(peripheral)
        }

        session?.phase = shouldKeepReconnecting ? .connecting : .disconnected
        session?.detailMessage = shouldKeepReconnecting
            ? "Connection paused. Swiftea will reconnect when the mug is available."
            : "Connection lost. You can retry the scan whenever you are ready."
        if let error {
            AppLog.bluetooth.notice(
                "Disconnected from mug \(peripheral.name ?? "unknown", privacy: .private); system reconnecting: \(shouldKeepReconnecting, privacy: .public); error: \(error.localizedDescription, privacy: .private)"
            )
        } else {
            AppLog.bluetooth.notice(
                "Disconnected from mug \(peripheral.name ?? "unknown", privacy: .private); system reconnecting: \(shouldKeepReconnecting, privacy: .public)."
            )
        }
        publishSnapshot(for: session)

        if !shouldKeepReconnecting,
           autoConnectPeripheralIdentifiers.contains(peripheral.identifier) {
            recoverExistingConnectionsAndAutoConnectIfPossible()
        }
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

        AppLog.bluetooth.info("Discovered services for mug \(session.name, privacy: .private).")
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
                session.peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        synchronizeConnectionMonitoring()
        session.detailMessage = "Connected. Waiting for the first live readings from your mug."
        publishSnapshot(for: session)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let session = sessionsByIdentifier[peripheral.identifier] else { return }

        guard error == nil else {
            session.detailMessage = "Connected, but one of the mug readings failed to update."
            AppLog.bluetooth.error("A mug characteristic value update failed.")
            publishSnapshot(for: session, coalescingReadings: true)
            return
        }

        handle(characteristic: characteristic, for: session)
        if session.hasDashboardReading {
            session.cancelConnectionTimeout()
            session.phase = .connected
            synchronizeConnectionMonitoring()
            session.detailMessage = "Connected. Live mug values are updating."
        } else {
            session.detailMessage = "Connected. Waiting for the first live readings from your mug."
        }
        publishSnapshot(for: session, coalescingReadings: true)
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
            AppLog.bluetooth.error("Notification state update failed for characteristic \(characteristic.uuid.uuidString, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return
        }

        AppLog.bluetooth.debug("Notification state updated for characteristic \(characteristic.uuid.uuidString, privacy: .private). Notifying: \(characteristic.isNotifying).")
    }

    private static func targetTemperatureLabel(for celsius: Double) -> String {
        celsius.formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}
