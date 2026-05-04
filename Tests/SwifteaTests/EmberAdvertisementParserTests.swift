import Foundation
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
}
