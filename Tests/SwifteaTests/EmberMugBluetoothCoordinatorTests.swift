import Foundation
import Testing
@testable import Swiftea

struct EmberMugBluetoothCoordinatorTests {
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
