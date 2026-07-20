import Foundation
import Testing
@testable import Swiftea

@Suite("Legal documents")
struct LegalDocumentsTests {
    @Test func generatedSourcesMatchCanonicalDocuments() throws {
        #expect(
            try canonicalDocument(named: "TERMS_OF_USE.md")
                == GeneratedLegalDocumentSources.termsOfUseMarkdown
        )
        #expect(
            try canonicalDocument(named: "SAFETY_NOTICE.md")
                == GeneratedLegalDocumentSources.safetyNoticeMarkdown
        )
        #expect(
            try canonicalDocument(named: "ACKNOWLEDGEMENTS.md")
                == GeneratedLegalDocumentSources.acknowledgementsMarkdown
        )
        #expect(
            try canonicalDocument(named: "LICENSE")
                == GeneratedLegalDocumentSources.licenseText
        )
    }

    @Test func acceptanceVersionsComeFromCanonicalMetadata() {
        #expect(SwifteaLegalDocuments.currentTermsVersion == "1.0")
        #expect(SwifteaLegalDocuments.currentSafetyNoticeVersion == "1.0")
        #expect(SwifteaLegalDocuments.termsOfUse.metadata.contains("Effective July 18, 2026"))
        #expect(SwifteaLegalDocuments.safetyNotice.metadata.contains("Effective July 18, 2026"))
    }

    private func canonicalDocument(named name: String) throws -> String {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = rootURL.appendingPathComponent(name)
        var source = try String(contentsOf: fileURL, encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")

        while source.hasSuffix("\n") {
            source.removeLast()
        }

        return source
    }
}
