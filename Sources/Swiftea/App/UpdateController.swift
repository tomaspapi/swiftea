import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdateController {
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
        Self.currentVersionDescription(in: bundle)
    }

    var automaticallyChecksForUpdates: Bool {
        updater?.automaticallyChecksForUpdates ?? updaterSettings.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        if let updater {
            updater.automaticallyChecksForUpdates = isEnabled
        } else {
            updaterSettings.automaticallyChecksForUpdates = isEnabled
        }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
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

    private static func currentVersionDescription(in bundle: Bundle) -> String {
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?) where build != version:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "Unknown"
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

    let currentVersionDescription: String

    private let updateController: UpdateController
    private var cancellables: Set<AnyCancellable> = []

    init(updateController: UpdateController) {
        self.updateController = updateController
        currentVersionDescription = updateController.currentVersionDescription
        canCheckForUpdates = updateController.updater?.canCheckForUpdates ?? false
        automaticallyChecksForUpdates = updateController.automaticallyChecksForUpdates

        guard let updater = updateController.updater else {
            return
        }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
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
