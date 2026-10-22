import Foundation

extension TerminalNativeTextSnapshot {
    /// The link that covers `offset`, joined across rows the terminal soft-wrapped.
    /// Word selection splits a URL at every `/`, `.` and `:`, so a press on a link
    /// would otherwise select only one segment of it.
    func linkRange(containing offset: Int) -> NSRange? {
        guard offset >= 0, offset < length,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.link.rawValue
              ) else {
            return nil
        }

        let softWrapBreaks = softWrapBreakOffsets
        let source = text as NSString
        var joinedUnits: [unichar] = []
        var sourceOffsets: [Int] = []
        joinedUnits.reserveCapacity(source.length)
        sourceOffsets.reserveCapacity(source.length)
        for sourceOffset in 0..<source.length where !softWrapBreaks.contains(sourceOffset) {
            joinedUnits.append(source.character(at: sourceOffset))
            sourceOffsets.append(sourceOffset)
        }

        guard let joinedOffset = sourceOffsets.firstIndex(of: offset) else { return nil }
        let joinedText = String(utf16CodeUnits: joinedUnits, count: joinedUnits.count)
        let match = detector
            .matches(in: joinedText, range: NSRange(location: 0, length: joinedUnits.count))
            .first { NSLocationInRange(joinedOffset, $0.range) }
        guard let match, match.range.length > 0 else { return nil }

        let start = sourceOffsets[match.range.location]
        let end = sourceOffsets[match.range.location + match.range.length - 1] + 1
        return NSRange(location: start, length: end - start)
    }

    /// Selected text as the user expects to paste it: rows the terminal
    /// soft-wrapped are rejoined, while real line breaks stay.
    func copyText(in range: NSRange) -> String? {
        guard let selected = text(in: range) else { return nil }
        let clamped = clampedRange(range)
        let softWrapBreaks = softWrapBreakOffsets.filter { NSLocationInRange($0, clamped) }
        guard !softWrapBreaks.isEmpty else { return selected }

        let source = text as NSString
        var units: [unichar] = []
        units.reserveCapacity(clamped.length)
        for sourceOffset in clamped.location..<upperBound(of: clamped)
            where !softWrapBreaks.contains(sourceOffset) {
            units.append(source.character(at: sourceOffset))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }

    /// Offsets of the row separators that follow a full-width row. The snapshot
    /// reads rows one at a time and loses the terminal's wrap flag, and tmux
    /// redraws panes row by row anyway, so a row that fills every column is the
    /// reliable sign that its text continues on the next row.
    private var softWrapBreakOffsets: Set<Int> {
        Set(
            lines.dropLast()
                .filter { $0.utf16Length >= columns }
                .map { $0.startOffset + $0.utf16Length }
        )
    }
}
