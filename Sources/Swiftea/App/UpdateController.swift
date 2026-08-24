import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdateController {
    struct AutomaticUpdatePreferences: Equatable, Sendable {
        let checksEnabled: Bool
        let downloadsEnabled: Bool
    }

    enum AutomaticUpdatePreferenceChange: Equatable, Sendable {
        case checks(Bool)
        case downloads(Bool)
    }

    private let bundle: Bundle
    private let updaterSettings: SPUUpdaterSettings
    private let updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        updaterSettings = SPUUpdaterSettings(hostBundle: bundle)

        guard Self.hasRequiredSparkleConfiguration(in: bundle) else {
            updaterController = nil
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater? {
        updaterController?.updater
    }

    var currentVersionDescription: String {
        AppVersion.currentMarketingVersion(bundle: bundle)
    }

    var automaticallyChecksForUpdates: Bool {
        updater?.automaticallyChecksForUpdates ?? updaterSettings.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        updater?.automaticallyDownloadsUpdates ?? updaterSettings.automaticallyDownloadsUpdates
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        applyAutomaticUpdatePreferenceChange(.checks(isEnabled))
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        applyAutomaticUpdatePreferenceChange(.downloads(isEnabled))
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    nonisolated static func automaticUpdatePreferences(
        current: AutomaticUpdatePreferences,
        applying change: AutomaticUpdatePreferenceChange
    ) -> AutomaticUpdatePreferences {
        switch change {
        case let .checks(isEnabled):
            return AutomaticUpdatePreferences(
                checksEnabled: isEnabled,
                downloadsEnabled: isEnabled ? current.downloadsEnabled : false
            )
        case let .downloads(isEnabled):
            return AutomaticUpdatePreferences(
                checksEnabled: isEnabled ? true : current.checksEnabled,
                downloadsEnabled: isEnabled
            )
        }
    }

    private func applyAutomaticUpdatePreferenceChange(_ change: AutomaticUpdatePreferenceChange) {
        let current = AutomaticUpdatePreferences(
            checksEnabled: automaticallyChecksForUpdates,
            downloadsEnabled: automaticallyDownloadsUpdates
        )
        let desired = Self.automaticUpdatePreferences(current: current, applying: change)

        if desired.checksEnabled {
            setAutomaticChecks(desired.checksEnabled)
            setAutomaticDownloads(desired.downloadsEnabled)
        } else {
            setAutomaticDownloads(desired.downloadsEnabled)
            setAutomaticChecks(desired.checksEnabled)
        }
    }

    private func setAutomaticChecks(_ isEnabled: Bool) {
        if let updater {
            updater.automaticallyChecksForUpdates = isEnabled
        } else {
            updaterSettings.automaticallyChecksForUpdates = isEnabled
        }
    }

    private func setAutomaticDownloads(_ isEnabled: Bool) {
        if let updater {
            updater.automaticallyDownloadsUpdates = isEnabled
        } else {
            updaterSettings.automaticallyDownloadsUpdates = isEnabled
        }
    }

    private static func hasRequiredSparkleConfiguration(in bundle: Bundle) -> Bool {
        hasRequiredSparkleConfiguration(in: bundle.infoDictionary ?? [:])
    }

    nonisolated static func hasRequiredSparkleConfiguration(in infoDictionary: [String: Any]) -> Bool {
        guard
            let feedURLString = stringValue(for: "SUFeedURL", in: infoDictionary),
            let feedURL = URL(string: feedURLString),
            feedURL.scheme == "https",
            !feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        guard
            let publicKey = stringValue(for: "SUPublicEDKey", in: infoDictionary),
            !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        guard
            boolValue(for: "SURequireSignedFeed", in: infoDictionary),
            boolValue(for: "SUVerifyUpdateBeforeExtraction", in: infoDictionary),
            numberValue(for: "SUSignedFeedFailureExpirationInterval", in: infoDictionary) == 0
        else {
            return false
        }

        return true
    }

    private nonisolated static func stringValue(for key: String, in infoDictionary: [String: Any]) -> String? {
        infoDictionary[key] as? String
    }

    private nonisolated static func boolValue(for key: String, in infoDictionary: [String: Any]) -> Bool {
        switch infoDictionary[key] {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["1", "true", "yes"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        default:
            return false
        }
    }

    private nonisolated static func numberValue(for key: String, in infoDictionary: [String: Any]) -> Double? {
        switch infoDictionary[key] {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

}

struct CheckForUpdatesCommand: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater?

    init(updater: SPUUpdater?) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            updater?.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

@MainActor
final class UpdateSettingsViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    @Published var automaticallyDownloadsUpdates = false

    let currentVersionDescription: String

    private let updateController: UpdateController
    private var cancellables: Set<AnyCancellable> = []

    init(updateController: UpdateController) {
        self.updateController = updateController
        currentVersionDescription = updateController.currentVersionDescription
        canCheckForUpdates = updateController.updater?.canCheckForUpdates ?? false
        automaticallyChecksForUpdates = updateController.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updateController.automaticallyDownloadsUpdates

        guard let updater = updateController.updater else {
            return
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] automaticallyDownloadsUpdates in
                self?.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] automaticallyChecksForUpdates in
                self?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updateController.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updateController.setAutomaticallyChecksForUpdates(isEnabled)
        automaticallyChecksForUpdates = updateController.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updateController.automaticallyDownloadsUpdates
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        updateController.setAutomaticallyDownloadsUpdates(isEnabled)
        automaticallyChecksForUpdates = updateController.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updateController.automaticallyDownloadsUpdates
    }
}

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater?) {
        guard let updater else {
            canCheckForUpdates = false
            return
        }

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
    }
}
