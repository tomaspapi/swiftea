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
}
