import Foundation
import Testing
@testable import VVTerm

@MainActor
struct TerminalNativeTextSnapshotLinkTests {
    @Test
    func selectsWholeURLFromMiddleSegment() {
        let snapshot = makeSnapshot(
            ["Open https://github.com/vvterm/pull/42?x=1 now"],
            columns: 80
        )
        let url = "https://github.com/vvterm/pull/42?x=1"

        // Offset 16 sits on "github", which word selection would select alone.
        let range = snapshot.linkRange(containing: 16)

        #expect(range == NSRange(location: 5, length: (url as NSString).length))
    }

    @Test
    func selectsWholeURLFromPunctuationBetweenSegments() {
        let snapshot = makeSnapshot(["Open https://github.com/vvterm now"], columns: 80)

        // Offset 11 is the "/" after "https:", where word selection finds nothing.
        let range = snapshot.linkRange(containing: 11)

        #expect(range.flatMap(snapshot.copyText(in:)) == "https://github.com/vvterm")
    }

    @Test
    func returnsNilOutsideLinks() {
        let snapshot = makeSnapshot(["Open https://github.com/vvterm now"], columns: 80)

        #expect(snapshot.linkRange(containing: 1) == nil)
        #expect(snapshot.linkRange(containing: 31) == nil)
    }

    @Test
    func excludesTrailingSentencePunctuation() {
        let snapshot = makeSnapshot(["See https://vvterm.app/docs."], columns: 80)

        let range = snapshot.linkRange(containing: 10)

        #expect(range.flatMap(snapshot.copyText(in:)) == "https://vvterm.app/docs")
    }

    @Test
    func joinsLinkSoftWrappedAcrossFullWidthRow() {
        // The first row fills all 20 columns, so the terminal wrapped it.
        let snapshot = makeSnapshot(
            ["go https://vvterm.ap", "p/a/b?c=1 done"],
            columns: 20
        )

        let fromFirstRow = snapshot.linkRange(containing: 8)
        let fromSecondRow = snapshot.linkRange(containing: 23)

        #expect(fromFirstRow == fromSecondRow)
        #expect(fromFirstRow.flatMap(snapshot.copyText(in:)) == "https://vvterm.app/a/b?c=1")
    }

    @Test
    func doesNotJoinLinkAcrossHardLineBreak() {
        let snapshot = makeSnapshot(
            ["go https://vvterm.app", "path/next"],
            columns: 40
        )

        let range = snapshot.linkRange(containing: 8)

        #expect(range.flatMap(snapshot.copyText(in:)) == "https://vvterm.app")
    }

    @Test
    func copyTextKeepsHardLineBreaks() {
        let snapshot = makeSnapshot(["alpha", "beta"], columns: 20)

        #expect(snapshot.copyText(in: NSRange(location: 0, length: 10)) == "alpha\nbeta")
    }

    private func makeSnapshot(_ lines: [String], columns: Int) -> TerminalNativeTextSnapshot {
        TerminalNativeTextSnapshot(
            lines: lines,
            cellSize: CGSize(width: 10, height: 20),
            columns: columns
        )
    }
}
