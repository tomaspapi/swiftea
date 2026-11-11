import Foundation
import Testing
@testable import Swiftea

struct UpdateControllerTests {
    @MainActor @Test func prereleaseVersionIsVisibleInSettingsAndAbout() throws {
        try withVersionBundle(label: "beta 1") { bundle in
            #expect(AppVersion.currentMarketingVersion(bundle: bundle) == "0.4.2")
            #expect(AppVersion.currentDisplayVersion(bundle: bundle) == "0.4.2 beta 1")
            #expect(AppVersion.currentIdentifier(bundle: bundle) == "0.4.2 beta 1 (10.2)")
            #expect(UpdateController(bundle: bundle).currentVersionDescription == "0.4.2 beta 1")
            #expect(AppVersion.isPrereleaseIdentifier(AppVersion.currentIdentifier(bundle: bundle)))
        }
    }

    @Test(arguments: ["", "$(SWIFTEA_PRERELEASE_LABEL)"])
    func stableVersionDoesNotShowABuildSettingOrBetaLabel(label: String) throws {
        try withVersionBundle(label: label) { bundle in
            #expect(AppVersion.currentDisplayVersion(bundle: bundle) == "0.4.2")
            #expect(!AppVersion.isPrereleaseIdentifier(AppVersion.currentIdentifier(bundle: bundle)))
        }
    }

    @Test func prereleaseIdentifierKeepsNumericReleaseVersionSeparate() {
        for label in ["alpha 1", "beta 1", "beta 12", "rc 2"] {
            let identifier = "0.4.2 \(label) (10.2)"
            #expect(AppVersion.isPrereleaseIdentifier(identifier))
            #expect(AppVersion.marketingVersion(from: identifier) == "0.4.2")
        }
        #expect(!AppVersion.isPrereleaseIdentifier("0.4.2 (11)"))
        #expect(!AppVersion.isPrereleaseIdentifier("0.4.2 beta 0 (10.2)"))
    }

    private func withVersionBundle(label: String, body: (Bundle) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftea-version-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.tom.swiftea.version-test.\(UUID().uuidString)",
            "CFBundleShortVersionString": "0.4.2",
            "CFBundleVersion": "10.2",
            "CFBundlePackageType": "BNDL",
            "SwifteaPrereleaseLabel": label
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Info.plist"))
        try body(#require(Bundle(url: directory)))
    }

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
