import Foundation

enum PublishedChangelog {
    static func currentReleaseNotesMarkdown(
        bundle: Bundle = .main,
        version: String = AppVersion.currentMarketingVersion()
    ) -> String {
        releaseNotesMarkdown(from: bundledMarkdown(bundle: bundle), version: version)
    }

    static func bundledMarkdown(bundle: Bundle = .main) -> String {
        guard
            let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "- No published changelog is bundled with this build."
        }

        return markdown
    }

    static func releaseNotesMarkdown(from changelogMarkdown: String, version: String) -> String {
        if let currentSection = releaseSection(in: changelogMarkdown, matching: version) {
            return currentSection
        }

        if let latestPublishedSection = firstPublishedReleaseSection(in: changelogMarkdown) {
            return latestPublishedSection
        }

        return "- No published changelog is bundled with this build."
    }

    private static func releaseSection(in markdown: String, matching version: String) -> String? {
        sectionBodies(in: markdown).first { section in
            headingMatchesVersion(section.heading, version: version)
        }?.body.nilIfBlank
    }

    private static func firstPublishedReleaseSection(in markdown: String) -> String? {
        sectionBodies(in: markdown)
            .first { !$0.heading.localizedCaseInsensitiveContains("unreleased") }?
            .body
            .nilIfBlank
    }

    private static func sectionBodies(in markdown: String) -> [(heading: String, body: String)] {
        var sections: [(heading: String, body: [String])] = []
        var currentHeading: String?
        var currentBody: [String] = []

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## "), !line.hasPrefix("### ") {
                if let currentHeading {
                    sections.append((currentHeading, currentBody))
                }

                currentHeading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentBody = []
            } else if currentHeading != nil {
                currentBody.append(line)
            }
        }

        if let currentHeading {
            sections.append((currentHeading, currentBody))
        }

        return sections.map { heading, body in
            (heading, trimmedBody(from: body))
        }
    }

    private static func trimmedBody(from lines: [String]) -> String {
        var trimmedLines = lines

        while trimmedLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            trimmedLines.removeFirst()
        }

        while trimmedLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            trimmedLines.removeLast()
        }

        return trimmedLines.joined(separator: "\n")
    }

    private static func headingMatchesVersion(_ heading: String, version: String) -> Bool {
        let normalizedHeading = heading
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedHeading == version || normalizedHeading.hasPrefix("\(version) ")
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
