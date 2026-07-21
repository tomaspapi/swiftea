import Foundation

struct SwifteaLegalSection: Identifiable {
    let id: String
    let title: String
    let body: String

    init(_ title: String, body: String) {
        self.id = title
        self.title = title
        self.body = body
    }
}

struct SwifteaLegalDocument {
    let title: String
    let summary: String
    let metadata: String
    let version: String
    let sections: [SwifteaLegalSection]
}

struct SwifteaMarkdownDocument {
    struct Block: Identifiable {
        enum Content {
            case heading(String)
            case paragraph(String)
            case list([String])
        }

        let id: Int
        let content: Content
    }

    let title: String
    let blocks: [Block]
}

enum SwifteaLegalDocuments {
    static let termsOfUse = parseLegalDocument(
        GeneratedLegalDocumentSources.termsOfUseMarkdown,
        sourceName: "TERMS_OF_USE.md"
    )
    static let safetyNotice = parseLegalDocument(
        GeneratedLegalDocumentSources.safetyNoticeMarkdown,
        sourceName: "SAFETY_NOTICE.md"
    )
    static let privacyPolicy = parseLegalDocument(
        GeneratedLegalDocumentSources.privacyPolicyMarkdown,
        sourceName: "PRIVACY_POLICY.md"
    )
    static let acknowledgements = parseMarkdownDocument(
        GeneratedLegalDocumentSources.acknowledgementsMarkdown,
        sourceName: "ACKNOWLEDGEMENTS.md"
    )
    static let licenseText = GeneratedLegalDocumentSources.licenseText

    static let currentTermsVersion = termsOfUse.version
    static let currentSafetyNoticeVersion = safetyNotice.version

    private static func parseLegalDocument(
        _ source: String,
        sourceName: String
    ) -> SwifteaLegalDocument {
        let lines = source.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.hasPrefix("# ") else {
            preconditionFailure("\(sourceName) must begin with a level-one title.")
        }

        let title = String(firstLine.dropFirst(2))
        var cursor = 1
        skipBlankLines(in: lines, cursor: &cursor)

        let summary = readParagraph(in: lines, cursor: &cursor)
        skipBlankLines(in: lines, cursor: &cursor)

        guard cursor < lines.count else {
            preconditionFailure("\(sourceName) is missing version metadata.")
        }

        let metadata = lines[cursor]
            .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        cursor += 1

        guard metadata.hasPrefix("Version "),
              let version = metadata
                .dropFirst("Version ".count)
                .split(separator: "·", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespaces),
              !version.isEmpty else {
            preconditionFailure("\(sourceName) has invalid version metadata.")
        }

        var sections: [SwifteaLegalSection] = []

        while cursor < lines.count {
            skipBlankLines(in: lines, cursor: &cursor)
            guard cursor < lines.count else { break }

            let headingLine = lines[cursor]
            guard headingLine.hasPrefix("## ") else {
                preconditionFailure("\(sourceName) contains text outside a section.")
            }

            let heading = String(headingLine.dropFirst(3))
            cursor += 1
            skipBlankLines(in: lines, cursor: &cursor)
            let body = readSectionBody(in: lines, cursor: &cursor)

            guard !body.isEmpty else {
                preconditionFailure("\(sourceName) contains an empty section: \(heading)")
            }

            sections.append(SwifteaLegalSection(heading, body: body))
        }

        guard !summary.isEmpty, !sections.isEmpty else {
            preconditionFailure("\(sourceName) must contain a summary and sections.")
        }

        return SwifteaLegalDocument(
            title: title,
            summary: summary,
            metadata: metadata,
            version: version,
            sections: sections
        )
    }

    private static func parseMarkdownDocument(
        _ source: String,
        sourceName: String
    ) -> SwifteaMarkdownDocument {
        let lines = source.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.hasPrefix("# ") else {
            preconditionFailure("\(sourceName) must begin with a level-one title.")
        }

        var cursor = 1
        var blocks: [SwifteaMarkdownDocument.Block] = []

        while cursor < lines.count {
            skipBlankLines(in: lines, cursor: &cursor)
            guard cursor < lines.count else { break }

            let line = lines[cursor]
            let content: SwifteaMarkdownDocument.Block.Content

            if line.hasPrefix("## ") {
                content = .heading(String(line.dropFirst(3)))
                cursor += 1
            } else if line.hasPrefix("- ") {
                var items: [String] = []

                while cursor < lines.count, lines[cursor].hasPrefix("- ") {
                    items.append(String(lines[cursor].dropFirst(2)))
                    cursor += 1
                }

                content = .list(items)
            } else {
                content = .paragraph(readParagraph(in: lines, cursor: &cursor))
            }

            blocks.append(.init(id: blocks.count, content: content))
        }

        return SwifteaMarkdownDocument(
            title: String(firstLine.dropFirst(2)),
            blocks: blocks
        )
    }

    private static func skipBlankLines(in lines: [String], cursor: inout Int) {
        while cursor < lines.count, lines[cursor].isEmpty {
            cursor += 1
        }
    }

    private static func readParagraph(in lines: [String], cursor: inout Int) -> String {
        var paragraphLines: [String] = []

        while cursor < lines.count, !lines[cursor].isEmpty {
            paragraphLines.append(lines[cursor])
            cursor += 1
        }

        return paragraphLines.joined(separator: " ")
    }

    private static func readSectionBody(in lines: [String], cursor: inout Int) -> String {
        var bodyLines: [String] = []

        while cursor < lines.count, !lines[cursor].hasPrefix("## ") {
            bodyLines.append(lines[cursor])
            cursor += 1
        }

        while bodyLines.last?.isEmpty == true {
            bodyLines.removeLast()
        }

        return bodyLines
            .split(separator: "", omittingEmptySubsequences: true)
            .map { $0.joined(separator: " ") }
            .joined(separator: "\n\n")
    }
}
