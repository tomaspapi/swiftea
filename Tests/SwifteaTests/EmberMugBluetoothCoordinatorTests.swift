import CoreBluetooth
import Foundation
import Testing
@testable import Swiftea

struct EmberMugBluetoothCoordinatorTests {
    @Test(arguments: [BluetoothRuntimeSnapshot.DiscoveryPhase.connected, .connecting])
    func nativeDisconnectionOverridesCachedLiveState(phase: BluetoothRuntimeSnapshot.DiscoveryPhase) {
        #expect(EmberMugBluetoothCoordinator.maintenanceAction(
            phase: phase, peripheralState: .disconnected, mayReconnect: true,
            hasReadableCharacteristics: true, hasSetupDeadline: false
        ) == .markDisconnected)
    }

    @Test(arguments: [CBPeripheralState.connecting, .disconnecting])
    func maintenanceDoesNotCancelOrRestartNativePendingRequests(state: CBPeripheralState) {
        #expect(EmberMugBluetoothCoordinator.maintenanceAction(
            phase: .connecting, peripheralState: state, mayReconnect: true,
            hasReadableCharacteristics: false, hasSetupDeadline: false
        ) == .wait)
    }

    @Test func failedSetupCanBeRecoveredWithoutOpeningAWindow() {
        #expect(EmberMugBluetoothCoordinator.maintenanceAction(
            phase: .failed, peripheralState: .connected, mayReconnect: true,
            hasReadableCharacteristics: false, hasSetupDeadline: false
        ) == .discoverServices)
        #expect(EmberMugBluetoothCoordinator.maintenanceAction(
            phase: .connecting, peripheralState: .connected, mayReconnect: true,
            hasReadableCharacteristics: false, hasSetupDeadline: true
        ) == .wait)
    }

    @Test func manualDisconnectAndDisabledAutoConnectAreNotUndoneByMaintenance() {
        for phase in [BluetoothRuntimeSnapshot.DiscoveryPhase.disconnected, .failed] {
            for state in [CBPeripheralState.connected, .disconnected] {
                #expect(EmberMugBluetoothCoordinator.maintenanceAction(
                    phase: phase, peripheralState: state, mayReconnect: false,
                    hasReadableCharacteristics: false, hasSetupDeadline: false
                ) == .wait)
            }
        }
        #expect(EmberMugBluetoothCoordinator.maintenanceAction(
            phase: .connected, peripheralState: .connected, mayReconnect: false,
            hasReadableCharacteristics: true, hasSetupDeadline: false
        ) == .read)
    }

    @Test func healthyEmptyMugRemainsConnectedAsLongAsReadingsArrive() {
        var health = MugReadingHealth(uptime: 0)
        let required = [EmberGATT.currentTemperature, EmberGATT.liquidState]
        for uptime in stride(from: 20.0, through: 26 * 60 * 60, by: 20) {
            for characteristic in required { health.record(characteristic, uptime: uptime) }
            #expect(health.action(requiredCharacteristics: required, uptime: uptime) == .read)
        }
    }

    @Test func staleEmptyStateGetsAReadBeforeConnectionReplacement() {
        var health = MugReadingHealth(uptime: 0)
        let required = [EmberGATT.currentTemperature, EmberGATT.liquidState]
        health.record(EmberGATT.currentTemperature, uptime: 100_000)
        #expect(health.action(requiredCharacteristics: required, uptime: 100_000) == .read)
        #expect(health.action(requiredCharacteristics: required, uptime: 100_019) == .read)
        #expect(health.action(requiredCharacteristics: required, uptime: 100_020) == .reconnect)
    }

    @Test func resumedMugCanAnswerProbeWithoutAnUnnecessaryReconnect() {
        var health = MugReadingHealth(uptime: 0)
        let required = [EmberGATT.currentTemperature, EmberGATT.liquidState]
        #expect(health.action(requiredCharacteristics: required, uptime: 100_000) == .read)
        for characteristic in required { health.record(characteristic, uptime: 100_001) }
        #expect(health.action(requiredCharacteristics: required, uptime: 100_020) == .read)
        #expect(health.action(requiredCharacteristics: required, uptime: 100_100) == .read)
        #expect(health.action(requiredCharacteristics: required, uptime: 100_120) == .reconnect)
    }

    @Test func batteryAndPushEventsCannotMaskStaleLiquidReadings() {
        var health = MugReadingHealth(uptime: 0)
        let required = [EmberGATT.currentTemperature, EmberGATT.liquidState]
        for uptime in [90.0, 110] {
            for characteristic in [EmberGATT.battery, EmberGATT.pushEvent, EmberGATT.targetTemperature,
                                   EmberGATT.currentTemperature, EmberGATT.contentsLevel] {
                health.record(characteristic, uptime: uptime)
            }
            let expected: MugReadingHealth.Action = uptime == 90 ? .read : .reconnect
            #expect(health.action(requiredCharacteristics: required, uptime: uptime) == expected)
        }
    }

    @MainActor @Test func backgroundMonitorRunsWithoutAnyWindowOrActivationEvent() async throws {
        var checks = 0
        var activities = 0
        var endedActivities = 0
        let monitor = MugConnectionMonitor(
            interval: 0.01,
            beginActivity: { options in
                #expect(options == .userInitiatedAllowingIdleSystemSleep)
                #expect(!options.contains(.idleSystemSleepDisabled))
                #expect(!options.contains(.idleDisplaySleepDisabled))
                activities += 1
                return NSObject()
            },
            endActivity: { _ in endedActivities += 1 },
            onCheck: { checks += 1 }
        )
        monitor.setEnabled(true)
        monitor.setEnabled(true)
        let deadline = Date().addingTimeInterval(2)
        while checks < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(checks >= 2)
        #expect(activities == 1)
        monitor.setEnabled(false)
        monitor.setEnabled(false)
        let stoppedCount = checks
        try await Task.sleep(for: .milliseconds(40))
        #expect(checks == stoppedCount)
        #expect(endedActivities == 1)
        monitor.setEnabled(true)
        #expect(activities == 2)
        monitor.setEnabled(false)
        #expect(endedActivities == 2)
    }

    @MainActor @Test func disposingMonitorReleasesTimerAndActivity() async throws {
        var checks = 0
        var endedActivities = 0
        var monitor: MugConnectionMonitor? = MugConnectionMonitor(
            interval: 0.01,
            beginActivity: { _ in NSObject() },
            endActivity: { _ in endedActivities += 1 },
            onCheck: { checks += 1 }
        )
        weak let releasedMonitor = monitor
        monitor?.setEnabled(true)
        monitor = nil
        #expect(releasedMonitor == nil)
        #expect(endedActivities == 1)
        try await Task.sleep(for: .milliseconds(40))
        #expect(checks == 0)
    }

    @Test func pushEventFloodCannotQueueUnlimitedFollowUpReads() {
        var budget = PushReadBudget()
        var accepted = 0
        for _ in 0 ..< 10_000 {
            if budget.admit(EmberGATT.currentTemperature, uptime: 100) { accepted += 1 }
        }
        #expect(accepted == 1)
        let anotherCharacteristic = budget.admit(EmberGATT.battery, uptime: 100)
        let refreshed = budget.admit(EmberGATT.currentTemperature, uptime: 101)
        #expect(anotherCharacteristic)
        #expect(refreshed)
    }

    @Test func discoveryCacheStaysBoundedDuringIdentityFloods() {
        var cache = DiscoveryCandidateCache<Int>()
        let now = Date()
        for index in 0 ..< 10_000 {
            cache.register(index, identifier: UUID(), now: now.addingTimeInterval(Double(index) / 1_000))
            #expect(cache.count <= cache.maximumCount)
        }
        #expect(cache.count == 32)
        #expect(cache.values.contains(9_999))
        cache.removeAll()
        #expect(cache.isEmpty)
    }

    @Test func discoveryCacheRefreshesKnownCandidatesAndExpiresAbsentOnes() {
        var cache = DiscoveryCandidateCache<Int>(maximumCount: 2, lifetime: 90)
        let first = UUID()
        let second = UUID()
        let now = Date()
        cache.register(1, identifier: first, now: now)
        cache.register(2, identifier: second, now: now)
        cache.register(3, identifier: first, now: now.addingTimeInterval(60))
        cache.expire(now: now.addingTimeInterval(90))
        #expect(cache[first] == 3)
        #expect(cache[second] == nil)
        #expect(cache.count == 1)
    }

    @Test func temperatureParsesLittleEndianCenticelsius() {
        #expect(EmberMugBluetoothCoordinator.temperature(from: Data([0x7C, 0x15])) == 55.0)
        #expect(EmberMugBluetoothCoordinator.temperature(from: Data([0x88, 0x13])) == 50.0)
        #expect(EmberMugBluetoothCoordinator.temperature(from: Data([0x1A, 0x14])) == 51.46)
    }

    @Test func temperatureRequiresAtLeastTwoBytes() {
        #expect(EmberMugBluetoothCoordinator.temperature(from: Data()) == nil)
        #expect(EmberMugBluetoothCoordinator.temperature(from: Data([0x7C])) == nil)
    }

    @Test func temperatureIgnoresExtraBytesAfterValue() {
        #expect(EmberMugBluetoothCoordinator.temperature(from: Data([0x7C, 0x15, 0xFF])) == 55.0)
    }

    @Test func serialNumberSkipsMugIdentifierAndMetadataByte() {
        let payload = Data([
            0xEB, 0x2C, 0xE1, 0x43, 0xAF, 0xA8,
            0x50,
            0x53, 0x53, 0x59, 0x33, 0x33, 0x33, 0x30, 0x30, 0x32, 0x32, 0x36
        ])

        #expect(EmberMugBluetoothCoordinator.serialNumber(from: payload) == "SSY33300226")
    }

    @Test func serialNumberRequiresBytesAfterCharacteristicPrefix() {
        let prefixOnlyPayload = Data([0xEB, 0x2C, 0xE1, 0x43, 0xAF, 0xA8, 0x50])

        #expect(EmberMugBluetoothCoordinator.serialNumber(from: prefixOnlyPayload) == nil)
    }
}
