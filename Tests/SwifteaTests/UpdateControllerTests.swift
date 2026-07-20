import Foundation
import Testing
@testable import Swiftea

struct UpdateControllerTests {
    @Test func sparkleConfigurationRequiresSignedFeedHardening() {
        let info: [String: Any] = [
            "SUFeedURL": "https://tomaspapi.github.io/swiftea/appcast.xml",
            "SUPublicEDKey": "public-key",
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0
        ]

        #expect(UpdateController.hasRequiredSparkleConfiguration(in: info))
    }

    @Test func sparkleConfigurationAcceptsXcodeBuildSettingValues() {
        let info: [String: Any] = [
            "SUFeedURL": "https://tomaspapi.github.io/swiftea/appcast.xml",
            "SUPublicEDKey": "public-key",
            "SURequireSignedFeed": "YES",
            "SUVerifyUpdateBeforeExtraction": "YES",
            "SUSignedFeedFailureExpirationInterval": "0"
        ]

        #expect(UpdateController.hasRequiredSparkleConfiguration(in: info))
    }

    @Test func sparkleConfigurationRejectsUnsignedFeedMetadata() {
        let baseInfo: [String: Any] = [
            "SUFeedURL": "https://tomaspapi.github.io/swiftea/appcast.xml",
            "SUPublicEDKey": "public-key",
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0
        ]

        #expect(!UpdateController.hasRequiredSparkleConfiguration(in: baseInfo))
    }

    @Test func sparkleConfigurationRejectsSignedFeedSafeModeFallback() {
        let info: [String: Any] = [
            "SUFeedURL": "https://tomaspapi.github.io/swiftea/appcast.xml",
            "SUPublicEDKey": "public-key",
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 1
        ]

        #expect(!UpdateController.hasRequiredSparkleConfiguration(in: info))
    }

    @Test func sparkleConfigurationStillRequiresHttpsAndPublicKey() {
        let unsignedHTTPInfo: [String: Any] = [
            "SUFeedURL": "http://tomaspapi.github.io/swiftea/appcast.xml",
            "SUPublicEDKey": "public-key",
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0
        ]
        let missingPublicKeyInfo: [String: Any] = [
            "SUFeedURL": "https://tomaspapi.github.io/swiftea/appcast.xml",
            "SUPublicEDKey": "",
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0
        ]

        #expect(!UpdateController.hasRequiredSparkleConfiguration(in: unsignedHTTPInfo))
        #expect(!UpdateController.hasRequiredSparkleConfiguration(in: missingPublicKeyInfo))
    }
}
