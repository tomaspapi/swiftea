import Foundation
import Testing
@testable import Swiftea

struct UpdateControllerTests {
    @Test func appInfoPlistDefinesUpdateDefaultsAndDailySchedule() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = projectRoot.appendingPathComponent("Config/Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let info = try #require(propertyList as? [String: Any])

        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
        #expect(info["SUAllowsAutomaticUpdates"] == nil)
    }

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

    @Test func enablingAutomaticInstallationAlsoEnablesAutomaticChecks() {
        let current = UpdateController.AutomaticUpdatePreferences(
            checksEnabled: false,
            downloadsEnabled: false
        )

        let updated = UpdateController.automaticUpdatePreferences(
            current: current,
            applying: .downloads(true)
        )

        #expect(updated.checksEnabled)
        #expect(updated.downloadsEnabled)
    }

    @Test func disablingAutomaticChecksAlsoDisablesAutomaticInstallation() {
        let current = UpdateController.AutomaticUpdatePreferences(
            checksEnabled: true,
            downloadsEnabled: true
        )

        let updated = UpdateController.automaticUpdatePreferences(
            current: current,
            applying: .checks(false)
        )

        #expect(!updated.checksEnabled)
        #expect(!updated.downloadsEnabled)
    }
}
