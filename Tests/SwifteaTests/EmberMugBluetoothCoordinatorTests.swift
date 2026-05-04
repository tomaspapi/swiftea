import Foundation
import Testing
@testable import Swiftea

struct EmberMugBluetoothCoordinatorTests {
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
