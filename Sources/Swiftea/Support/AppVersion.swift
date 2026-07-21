import Foundation

enum AppVersion {
    static func currentMarketingVersion(bundle: Bundle = .main) -> String {
        normalizedBundleString("CFBundleShortVersionString", bundle: bundle) ?? "0.2.3"
    }

    static func currentBuildNumber(bundle: Bundle = .main) -> String? {
        normalizedBundleString(kCFBundleVersionKey as String, bundle: bundle)
    }

    static func currentIdentifier(bundle: Bundle = .main) -> String {
        let version = currentMarketingVersion(bundle: bundle)
        guard
            let build = currentBuildNumber(bundle: bundle),
            build != version
        else {
            return version
        }

        return "\(version) (\(build))"
    }

    private static func normalizedBundleString(_ key: String, bundle: Bundle) -> String? {
        (bundle.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
