import DocumentCore
import SyntaxKit

/// Finds the byte-offset pair of a matching bracket for a caret adjacent to
/// one of `()`, `[]`, `{}`. When `tokenRuns` is provided (a grammar is
/// active for the document), brackets inside `.string`/`.comment` runs are
/// invisible to the scan; when `nil` (no grammar, e.g. plain text), the
/// scan is a naive nested-depth count over every byte with no
/// string/comment awareness. Angle brackets are deliberately not
/// supported — see the plan/spec Non-Goals.
enum BracketMatcher {
    private static let pairs: [(open: UInt8, close: UInt8)] = [
        (UInt8(ascii: "("), UInt8(ascii: ")")),
        (UInt8(ascii: "["), UInt8(ascii: "]")),
        (UInt8(ascii: "{"), UInt8(ascii: "}")),
    ]

    static func match(
        in buffer: TextBuffer, at caret: ByteOffset, tokenRuns: [TokenRun]? = nil
    ) -> (open: ByteOffset, close: ByteOffset)? {
        if let after = character(in: buffer, at: caret), isReal(caret, tokenRuns) {
            if let pair = pairs.first(where: { $0.open == after }) {
                return findForward(in: buffer, openAt: caret, pair: pair, tokenRuns: tokenRuns)
            }
            if let pair = pairs.first(where: { $0.close == after }) {
                return findBackward(in: buffer, closeAt: caret, pair: pair, tokenRuns: tokenRuns)
            }
        }
        guard caret.value > 0 else { return nil }
        let before = ByteOffset(caret.value - 1)
        guard let beforeChar = character(in: buffer, at: before), isReal(before, tokenRuns) else { return nil }
        if let pair = pairs.first(where: { $0.close == beforeChar }) {
            return findBackward(in: buffer, closeAt: before, pair: pair, tokenRuns: tokenRuns)
        }
        if let pair = pairs.first(where: { $0.open == beforeChar }) {
            return findForward(in: buffer, openAt: before, pair: pair, tokenRuns: tokenRuns)
        }
        return nil
    }

    private static func findForward(
        in buffer: TextBuffer, openAt: ByteOffset,
        pair: (open: UInt8, close: UInt8), tokenRuns: [TokenRun]?
    ) -> (open: ByteOffset, close: ByteOffset)? {
        var depth = 1
        var offset = openAt.value + 1
        while offset < buffer.utf8Count {
            let position = ByteOffset(offset)
            if let byte = character(in: buffer, at: position), isReal(position, tokenRuns) {
                if byte == pair.open {
                    depth += 1
                } else if byte == pair.close {
                    depth -= 1
                    if depth == 0 {
                        return (openAt, position)
                    }
                }
            }
            offset += 1
        }
        return nil
    }

    private static func findBackward(
        in buffer: TextBuffer, closeAt: ByteOffset,
        pair: (open: UInt8, close: UInt8), tokenRuns: [TokenRun]?
    ) -> (open: ByteOffset, close: ByteOffset)? {
        var depth = 1
        var offset = closeAt.value - 1
        while offset >= 0 {
            let position = ByteOffset(offset)
            if let byte = character(in: buffer, at: position), isReal(position, tokenRuns) {
                if byte == pair.close {
                    depth += 1
                } else if byte == pair.open {
                    depth -= 1
                    if depth == 0 {
                        return (position, closeAt)
                    }
                }
            }
            offset -= 1
        }
        return nil
    }

    /// The raw byte at `offset`, or `nil` if `offset` is out of bounds, or
    /// `offset` falls inside (or immediately before) a multi-byte UTF-8
    /// scalar. `findForward`/`findBackward` advance one byte at a time
    /// regardless of scalar width, so this is reached at every byte
    /// position of multi-byte content, not just scalar starts — and
    /// `TextBuffer.slice(_:)` traps on a non-scalar-boundary range.
    /// Brackets are single-byte ASCII, so a genuine match can only occur
    /// at a scalar that is exactly 1 byte wide (both `offset` and
    /// `offset + 1` on scalar boundaries); anything else safely isn't a
    /// bracket and is skipped rather than sliced.
    private static func character(in buffer: TextBuffer, at offset: ByteOffset) -> UInt8? {
        guard offset.value >= 0, offset.value < buffer.utf8Count else { return nil }
        let next = ByteOffset(offset.value + 1)
        guard buffer.isScalarBoundary(offset), buffer.isScalarBoundary(next) else { return nil }
        return buffer.slice(offset ..< next).utf8.first
    }

    /// `true` when `offset` should be considered for matching: always true
    /// in fallback mode (`tokenRuns == nil`); in tree-aware mode, true
    /// unless `offset` falls inside a `.string` or `.comment` run.
    private static func isReal(_ offset: ByteOffset, _ tokenRuns: [TokenRun]?) -> Bool {
        guard let tokenRuns else { return true }
        guard let run = tokenRuns.first(where: { $0.range.contains(offset) }) else { return true }
        return run.type != .string && run.type != .comment
    }
}
