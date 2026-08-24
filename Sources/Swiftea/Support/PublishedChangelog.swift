import Foundation

enum PublishedChangelog {
    struct Release: Equatable, Identifiable {
        let version: String
        let notes: [String]

        var id: String {
            version
        }
    }

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

    static func releaseNoteItems(from markdown: String) -> [String] {
        var items: [String] = []
        var currentItem: String?

        func finishCurrentItem() {
            guard let item = currentItem?.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty else {
                currentItem = nil
                return
            }

            items.append(item)
            currentItem = nil
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                finishCurrentItem()
                currentItem = String(line.dropFirst(2))
            } else if line.isEmpty {
                finishCurrentItem()
            } else if currentItem != nil {
                currentItem = [currentItem, line]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } else {
                currentItem = line
            }
        }

        finishCurrentItem()
        return items
    }

    static func releases(
        from changelogMarkdown: String,
        newerThan previousVersion: String?,
        through currentVersion: String
    ) -> [Release] {
        let current = NumericVersion(currentVersion)
        let previous = previousVersion.flatMap(NumericVersion.init)

        return sectionBodies(in: changelogMarkdown)
            .compactMap { section -> (release: Release, version: NumericVersion)? in
                guard
                    let versionString = versionString(from: section.heading),
                    let version = NumericVersion(versionString),
                    !releaseNoteItems(from: section.body).isEmpty
                else {
                    return nil
                }

                return (
                    Release(
                        version: versionString,
                        notes: releaseNoteItems(from: section.body)
                    ),
                    version
                )
            }
            .filter { item in
                guard let current else { return false }
                guard item.version <= current else { return false }
                guard let previous else {
                    return item.version == current
                }
                return item.version > previous
            }
            .sorted { $0.version > $1.version }
            .map(\.release)
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

    private static func versionString(from heading: String) -> String? {
        let candidate = heading
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        guard let candidate, NumericVersion(candidate) != nil else {
            return nil
        }

        return candidate
    }
}

private struct NumericVersion: Comparable {
    private let components: [Int]

    init?(_ string: String) {
        let parsedComponents = string
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)

        guard
            !parsedComponents.isEmpty,
            parsedComponents.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }

        components = parsedComponents.compactMap(Int.init)
    }

    static func < (lhs: NumericVersion, rhs: NumericVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)

        for index in 0 ..< count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
