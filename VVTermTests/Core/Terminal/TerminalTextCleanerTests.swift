import Foundation
import Testing
@testable import VVTerm

struct TerminalTextCleanerTests {
    private let settings = TerminalCopySettings()

    @Test
    func joinsLinkHardWrappedAcrossLines() {
        let copied = "https://vvterm.app/docs/a\nb/c?d=1\ne=2"

        #expect(TerminalTextCleaner.cleanText(copied, settings: settings) == "https://vvterm.app/docs/ab/c?d=1e=2")
    }

    @Test
    func joinsIndentedLinkContinuationLines() {
        let copied = "  https://vvterm.app/docs/a  \r\n    b/c?d=1\n"

        #expect(TerminalTextCleaner.cleanText(copied, settings: settings) == "https://vvterm.app/docs/ab/c?d=1")
    }

    @Test
    func keepsLineBreakBetweenSeparateLinks() {
        let copied = "https://vvterm.app/a\nhttps://vvterm.app/b"

        #expect(TerminalTextCleaner.cleanText(copied, settings: settings) == copied)
    }

    @Test
    func keepsLineBreakWhenTextFollowsLink() {
        let copied = "https://vvterm.app/a\nnext step here"

        #expect(TerminalTextCleaner.cleanText(copied, settings: settings) == copied)
    }

    @Test
    func keepsLineBreakAroundBlankLine() {
        let copied = "https://vvterm.app/a\n\nb"

        #expect(TerminalTextCleaner.cleanText(copied, settings: settings) == copied)
    }

    @Test
    func keepsMultilinePlainText() {
        let copied = "alpha\nbeta"

        #expect(TerminalTextCleaner.cleanText(copied, settings: settings) == copied)
    }
}
