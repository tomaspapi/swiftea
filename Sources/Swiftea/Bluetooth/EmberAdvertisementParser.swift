import CoreBluetooth
import Foundation

enum EmberMugFinish: String, Equatable {
    case sageGreen = "Sage Green"
    case sandstone = "Sandstone"
    case black = "Black"
    case white = "White"
    case grey = "Grey"
    case blue = "Blue"
    case red = "Red"
    case copper = "Copper"
    case gold = "Gold"
    case stainlessSteel = "Stainless Steel"
    case roseGold = "Rose Gold"
}

enum EmberMugSize: String, Equatable {
    case ounce6 = "6 oz"
    case ounce10 = "10 oz"
    case ounce12 = "12 oz"
    case ounce14 = "14 oz"
    case ounce16 = "16 oz"
}

enum EmberAdvertisementTrust: Equatable {
    case serviceBacked
    case nameOnly
    case unrelated
}

enum EmberAdvertisementParser {
    private static let emberManufacturerID: UInt16 = 0x03C1
    private static let testingManufacturerID: UInt16 = 0xFFFF
    private static let mainServiceUUID = "FC543622-236C-4C94-8FA9-944A3E5353FA"
    private static let travelMugServiceUUIDs: Set<String> = [
        "FC543621-236C-4C94-8FA9-944A3E5353FA",
        "FC5421A1-236C-4C94-8FA9-944A3E5353FA"
    ]
    private static let knownServiceUUIDs: Set<String> = travelMugServiceUUIDs.union([mainServiceUUID])

    static var discoveryServiceUUIDs: [CBUUID] {
        knownServiceUUIDs
            .sorted()
            .map(CBUUID.init(string:))
    }

    static func trust(from advertisementData: [String: Any], peripheralName: String?) -> EmberAdvertisementTrust {
        if hasEmberServiceEvidence(in: advertisementData) {
            return .serviceBacked
        }

        if likelyName(from: advertisementData, peripheralName: peripheralName) != nil {
            return .nameOnly
        }

        return .unrelated
    }

    static func likelyName(from advertisementData: [String: Any], peripheralName: String?) -> String? {
        if let advertisedLocalName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           isLikelyEmberName(advertisedLocalName) {
            return advertisedLocalName
        }

        if let peripheralName, isLikelyEmberName(peripheralName) {
            return peripheralName
        }

        return nil
    }

    static func serviceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
        (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    }

    static func finish(from advertisementData: [String: Any]) -> EmberMugFinish? {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return nil
        }

        return finish(fromManufacturerData: manufacturerData)
    }

    static func size(from advertisementData: [String: Any]) -> EmberMugSize? {
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let serviceUUIDs = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []).map(\.uuidString)
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String

        return size(
            fromManufacturerData: manufacturerData,
            serviceUUIDs: serviceUUIDs,
            localName: localName
        )
    }

    static func finish(fromManufacturerData manufacturerData: Data) -> EmberMugFinish? {
        guard let modelData = emberModelData(fromManufacturerData: manufacturerData) else {
            return nil
        }

        if modelData.count < 4 {
            return finish(fromColourID: signedBigEndianInteger(from: modelData))
        }

        let colourIndex = modelData.index(modelData.startIndex, offsetBy: 3)
        return finish(fromColourID: Int(modelData[colourIndex]))
    }

    static func size(
        fromManufacturerData manufacturerData: Data?,
        serviceUUIDs: [String] = [],
        localName: String? = nil
    ) -> EmberMugSize? {
        if let manufacturerData, let modelData = emberModelData(fromManufacturerData: manufacturerData) {
            if modelData.count < 4 {
                return size(fromLegacyModelID: signedBigEndianInteger(from: modelData), serviceUUIDs: serviceUUIDs)
            }

            let modelIDIndex = modelData.index(modelData.startIndex, offsetBy: 1)
            let generationIndex = modelData.index(modelData.startIndex, offsetBy: 2)
            return size(
                fromModelID: Int(modelData[modelIDIndex]),
                generation: Int(modelData[generationIndex])
            )
        }

        return size(guessingFromLocalName: localName)
    }

    private static func emberModelData(fromManufacturerData manufacturerData: Data) -> Data? {
        guard manufacturerData.count > 2 else { return nil }

        let manufacturerID = manufacturerID(from: manufacturerData)

        guard manufacturerID == emberManufacturerID || manufacturerID == testingManufacturerID else {
            return nil
        }

        return Data(manufacturerData.dropFirst(2))
    }

    private static func hasEmberServiceEvidence(in advertisementData: [String: Any]) -> Bool {
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerID(from: manufacturerData) == emberManufacturerID {
            return true
        }

        if serviceUUIDs(from: advertisementData).contains(where: isEmberServiceUUID) {
            return true
        }

        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           serviceData.keys.contains(where: isEmberServiceUUID) {
            return true
        }

        return false
    }

    private static func manufacturerID(from manufacturerData: Data) -> UInt16? {
        guard manufacturerData.count > 2 else { return nil }

        return UInt16(manufacturerData[manufacturerData.startIndex])
            | (UInt16(manufacturerData[manufacturerData.index(after: manufacturerData.startIndex)]) << 8)
    }

    private static func isEmberServiceUUID(_ uuid: CBUUID) -> Bool {
        let normalizedUUID = uuid.uuidString.uppercased()
        return knownServiceUUIDs.contains(normalizedUUID)
            || normalizedUUID.hasPrefix("FC54")
    }

    private static func isLikelyEmberName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("ember")
            || name.localizedCaseInsensitiveContains("mug")
    }

    private static func size(fromLegacyModelID modelID: Int, serviceUUIDs: [String]) -> EmberMugSize? {
        if !travelMugServiceUUIDs.isDisjoint(with: serviceUUIDs) {
            return .ounce12
        }

        switch modelID {
        case 1, 2, 3, -127, -126, -125, -124, -123, -122, -120, -117, -57, -56, -55, -53, -52, 83, 131:
            return .ounce10
        case 65, -51, -59, -63, -61, -62, 120:
            return .ounce14
        case -60:
            return .ounce6
        default:
            return nil
        }
    }

    private static func size(fromModelID modelID: Int, generation _: Int) -> EmberMugSize? {
        switch modelID {
        case 1:
            return .ounce10
        case 2, 120:
            return .ounce14
        case 3:
            return .ounce12
        case 8:
            return .ounce6
        case 9:
            return .ounce16
        default:
            return nil
        }
    }

    private static func size(guessingFromLocalName localName: String?) -> EmberMugSize? {
        guard let localName else { return nil }

        if localName.localizedCaseInsensitiveContains("travel") {
            return .ounce12
        }

        if localName.localizedCaseInsensitiveContains("cup") {
            return .ounce6
        }

        if localName.localizedCaseInsensitiveContains("tumbler") {
            return .ounce16
        }

        return nil
    }

    private static func signedBigEndianInteger(from data: Data) -> Int {
        guard !data.isEmpty else { return 0 }

        var value = 0
        for byte in data {
            value = (value << 8) | Int(byte)
        }

        let bitWidth = data.count * 8
        let signMask = 1 << (bitWidth - 1)
        if value & signMask != 0 {
            value -= 1 << bitWidth
        }

        return value
    }

    private static func finish(fromColourID colourID: Int) -> EmberMugFinish? {
        switch colourID {
        case -127, -63, 1, 14, 65:
            .black
        case -126, -62, 2, 130:
            .white
        case -120, -117, -56, -53, 8, 11:
            .red
        case -131, -125, -61, 3, 51, 83:
            .copper
        case -124, -60:
            .roseGold
        case -123, -59:
            .stainlessSteel
        case -51:
            .sandstone
        case -52:
            .sageGreen
        case -55:
            .grey
        case -57:
            .blue
        case -122:
            .gold
        default:
            nil
        }
    }
}
