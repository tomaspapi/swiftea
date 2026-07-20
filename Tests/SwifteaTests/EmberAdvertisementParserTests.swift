import Foundation
import CoreBluetooth
import Testing
@testable import Swiftea

struct EmberAdvertisementParserTests {
    @Test func parsesShortManufacturerPayloadForBlackMug() {
        let manufacturerData = Data([0xC1, 0x03, 0x81])

        let finish = EmberAdvertisementParser.finish(fromManufacturerData: manufacturerData)
        let size = EmberAdvertisementParser.size(fromManufacturerData: manufacturerData)

        #expect(finish == .black)
        #expect(size == .ounce10)
    }

    @Test func parsesExtendedManufacturerPayloadForCopperMug() {
        let manufacturerData = Data([0xC1, 0x03, 0x00, 0x78, 0x43, 0x33])

        let finish = EmberAdvertisementParser.finish(fromManufacturerData: manufacturerData)
        let size = EmberAdvertisementParser.size(fromManufacturerData: manufacturerData)

        #expect(finish == .copper)
        #expect(size == .ounce14)
    }

    @Test func parsesTravelMugSizeFromLegacyPayloadAndServiceUUID() {
        let manufacturerData = Data([0xC1, 0x03, 0x0B])

        let size = EmberAdvertisementParser.size(
            fromManufacturerData: manufacturerData,
            serviceUUIDs: ["FC543621-236C-4C94-8FA9-944A3E5353FA"]
        )

        #expect(size == .ounce12)
    }

    @Test func ignoresNonEmberManufacturerPayloads() {
        let manufacturerData = Data([0x4C, 0x00, 0x01, 0x02, 0x03])

        let finish = EmberAdvertisementParser.finish(fromManufacturerData: manufacturerData)
        let size = EmberAdvertisementParser.size(fromManufacturerData: manufacturerData)

        #expect(finish == nil)
        #expect(size == nil)
    }

    @Test func treatsEmberManufacturerPayloadAsServiceBackedAdvertisement() {
        let advertisementData = [
            CBAdvertisementDataManufacturerDataKey: Data([0xC1, 0x03, 0x81])
        ] as [String: Any]

        #expect(EmberAdvertisementParser.trust(from: advertisementData, peripheralName: nil) == .serviceBacked)
    }

    @Test func treatsEmberServiceUUIDAsServiceBackedAdvertisement() {
        let advertisementData = [
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FC543622-236C-4C94-8FA9-944A3E5353FA")]
        ] as [String: Any]

        #expect(EmberAdvertisementParser.trust(from: advertisementData, peripheralName: nil) == .serviceBacked)
    }

    @Test func discoveryServiceFilterIncludesKnownEmberServices() {
        let serviceUUIDs = Set(EmberAdvertisementParser.discoveryServiceUUIDs.map(\.uuidString))

        #expect(serviceUUIDs.contains("FC543622-236C-4C94-8FA9-944A3E5353FA"))
        #expect(serviceUUIDs.contains("FC543621-236C-4C94-8FA9-944A3E5353FA"))
        #expect(serviceUUIDs.contains("FC5421A1-236C-4C94-8FA9-944A3E5353FA"))
    }

    @Test func treatsEmberServiceDataAsServiceBackedAdvertisement() {
        let advertisementData = [
            CBAdvertisementDataServiceDataKey: [
                CBUUID(string: "FC543622-236C-4C94-8FA9-944A3E5353FA"): Data([0x01])
            ]
        ] as [String: Any]

        #expect(EmberAdvertisementParser.trust(from: advertisementData, peripheralName: nil) == .serviceBacked)
    }

    @Test func treatsNameOnlyEmberAdvertisementAsNameOnly() {
        let advertisementData = [
            CBAdvertisementDataLocalNameKey: "Ember Mug"
        ] as [String: Any]

        #expect(EmberAdvertisementParser.trust(from: advertisementData, peripheralName: nil) == .nameOnly)
    }

    @Test func treatsUnrelatedAdvertisementAsUnrelated() {
        let advertisementData = [
            CBAdvertisementDataLocalNameKey: "Desk Speaker",
            CBAdvertisementDataManufacturerDataKey: Data([0x4C, 0x00, 0x01, 0x02, 0x03])
        ] as [String: Any]

        #expect(EmberAdvertisementParser.trust(from: advertisementData, peripheralName: nil) == .unrelated)
    }

    @Test func broadDiscoveryRejectsNameOnlyCandidates() {
        #expect(EmberMugBluetoothCoordinator.shouldRegisterDiscoveredCandidate(trust: .nameOnly, isSavedTarget: false) == false)
    }

    @Test func savedMugScanCanAcceptNameOnlyCandidateForKnownIdentifier() {
        #expect(EmberMugBluetoothCoordinator.shouldRegisterDiscoveredCandidate(trust: .nameOnly, isSavedTarget: true))
    }

    @Test func broadDiscoveryAcceptsServiceBackedCandidates() {
        #expect(EmberMugBluetoothCoordinator.shouldRegisterDiscoveredCandidate(trust: .serviceBacked, isSavedTarget: false))
    }
}
