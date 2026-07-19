import DocumentCore
import Foundation

/// High-performance search & replace engine operating over `TextBuffer`.
public final class SearchEngine: Sendable {
    public init() {}

    /// Finds all occurrences of `query` in `buffer` matching `options`.
    public func findAll(
        query: String,
        in buffer: TextBuffer,
        options: SearchOptions = [],
    ) -> [SearchMatch] {
        guard !query.isEmpty else { return [] }

        let text = buffer.string
        let nsString = text as NSString

        if options.contains(.regularExpression) {
            return findRegexMatches(query: query, in: buffer, nsString: nsString, text: text, options: options)
        } else {
            return findLiteralMatches(query: query, in: buffer, nsString: nsString, options: options)
        }
    }

    /// Finds the next match after `startingAt` offset, wrapping around if needed.
    public func findNext(
        query: String,
        startingAt offset: ByteOffset,
        in buffer: TextBuffer,
        options: SearchOptions = [],
    ) -> SearchMatch? {
        let allMatches = findAll(query: query, in: buffer, options: options)
        guard !allMatches.isEmpty else { return nil }

        if let next = allMatches.first(where: { $0.range.lowerBound >= offset }) {
            return next
        }
        return allMatches.first
    }

    /// Finds the previous match before `startingAt` offset, wrapping around if needed.
    public func findPrevious(
        query: String,
        startingAt offset: ByteOffset,
        in buffer: TextBuffer,
        options: SearchOptions = [],
    ) -> SearchMatch? {
        let allMatches = findAll(query: query, in: buffer, options: options)
        guard !allMatches.isEmpty else { return nil }

        if let previous = allMatches.last(where: { $0.range.lowerBound < offset }) {
            return previous
        }
        return allMatches.last
    }

    /// Builds an atomic `EditTransaction` to replace `matches` with `replacement`.
    public func buildReplaceTransaction(
        matches: [SearchMatch],
        replacement: String,
        in buffer: TextBuffer,
        origin: EditOrigin = .replaceAll,
    ) -> EditTransaction {
        let sorted = matches.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
        var edits: [Edit] = []

        var lastEnd = ByteOffset(0)
        for match in sorted {
            guard match.range.lowerBound >= lastEnd else { continue }
            edits.append(Edit(range: match.range.lowerBound ..< match.range.upperBound, replacement: replacement))
            lastEnd = match.range.upperBound
        }

        return EditTransaction(
            baseVersion: buffer.version,
            edits: edits,
            selectionBefore: .empty,
            selectionAfter: .empty,
            coalescingKey: nil,
            origin: origin,
        )
    }

    private func findRegexMatches(
        query: String,
        in buffer: TextBuffer,
        nsString: NSString,
        text: String,
        options: SearchOptions,
    ) -> [SearchMatch] {
        var regexOptions: NSRegularExpression.Options = []
        if !options.contains(.caseSensitive) {
            regexOptions.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: query, options: regexOptions) else {
            return []
        }

        let fullRange = NSRange(location: 0, length: nsString.length)
        let results = regex.matches(in: text, options: [], range: fullRange)
        var matches: [SearchMatch] = []

        for result in results {
            let range = result.range
            guard range.location != NSNotFound, range.length >= 0 else { continue }

            let startByte = buffer.byteOffset(of: UTF16Offset(range.location))
            let endByte = buffer.byteOffset(of: UTF16Offset(range.location + range.length))

            if options.contains(.wholeWord), !isWholeWord(range: range, in: nsString) {
                continue
            }

            let lineIndex = buffer.linePosition(of: startByte).line
            matches.append(SearchMatch(range: startByte ..< endByte, lineIndex: lineIndex))
        }
        return matches
    }

    private func findLiteralMatches(
        query: String,
        in buffer: TextBuffer,
        nsString: NSString,
        options: SearchOptions,
    ) -> [SearchMatch] {
        var searchOptions: NSString.CompareOptions = []
        if !options.contains(.caseSensitive) {
            searchOptions.insert(.caseInsensitive)
        }

        var matches: [SearchMatch] = []
        var searchRange = NSRange(location: 0, length: nsString.length)

        while searchRange.location < nsString.length {
            let foundRange = nsString.range(of: query, options: searchOptions, range: searchRange)
            if foundRange.location == NSNotFound {
                break
            }

            let startByte = buffer.byteOffset(of: UTF16Offset(foundRange.location))
            let endByte = buffer.byteOffset(of: UTF16Offset(foundRange.location + foundRange.length))

            if !options.contains(.wholeWord) || isWholeWord(range: foundRange, in: nsString) {
                let lineIndex = buffer.linePosition(of: startByte).line
                matches.append(SearchMatch(range: startByte ..< endByte, lineIndex: lineIndex))
            }

            searchRange.location = foundRange.location + max(1, foundRange.length)
            searchRange.length = nsString.length - searchRange.location
        }
        return matches
    }

    private func isWholeWord(range: NSRange, in nsString: NSString) -> Bool {
        if range.location > 0 {
            let prevChar = nsString.character(at: range.location - 1)
            if let scalar = UnicodeScalar(prevChar), CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return false
            }
        }
        let afterIndex = range.location + range.length
        if afterIndex < nsString.length {
            let nextChar = nsString.character(at: afterIndex)
            if let scalar = UnicodeScalar(nextChar), CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return false
            }
        }
        return true
    }
}
