import Testing
@testable import Swiftea

struct PublishedChangelogTests {
    @Test func releaseNoteItemsPreserveEachMarkdownBullet() {
        let markdown = """
        - First improvement.
        - Second improvement.
        - Third improvement.
        """

        #expect(PublishedChangelog.releaseNoteItems(from: markdown) == [
            "First improvement.",
            "Second improvement.",
            "Third improvement."
        ])
    }

    @Test func releaseNoteItemsJoinWrappedBulletLines() {
        let markdown = """
        - This release note wraps
          onto a second source line.
        - Another change.
        """

        #expect(PublishedChangelog.releaseNoteItems(from: markdown) == [
            "This release note wraps onto a second source line.",
            "Another change."
        ])
    }

    @Test func releasesIncludeEveryVersionMissedInNewestFirstOrder() {
        let markdown = """
        # Changelog

        ## Unreleased

        - Not shipped.

        ## 0.3.0 — 2026-08-01

        - Latest change.

        ## 0.2.1

        - Corrective change.
        - Another correction.

        ## 0.2.0

        - Major change.

        ## 0.1.0

        - Initial release.
        """

        let releases = PublishedChangelog.releases(
            from: markdown,
            newerThan: "0.1.0",
            through: "0.3.0"
        )

        #expect(releases == [
            .init(version: "0.3.0", notes: ["Latest change."]),
            .init(version: "0.2.1", notes: ["Corrective change.", "Another correction."]),
            .init(version: "0.2.0", notes: ["Major change."])
        ])
    }

    @Test func releasesUseOnlyCurrentVersionWhenPreviousVersionIsUnknown() {
        let markdown = """
        ## 2.0.0

        - Current.

        ## 1.0.0

        - Old.
        """

        #expect(PublishedChangelog.releases(
            from: markdown,
            newerThan: nil,
            through: "2.0.0"
        ) == [
            .init(version: "2.0.0", notes: ["Current."])
        ])
    }
}
