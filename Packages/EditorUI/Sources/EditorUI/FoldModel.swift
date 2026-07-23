import DocumentCore
import SyntaxKit

/// Gutter mark for a line (spec: FoldModel).
public enum FoldGutterMark: Equatable {
    case none, foldable, folded
}

/// Per-pane fold state (spec: FoldModel). Pure value type — no AppKit, no
/// engine knowledge — so property tests can drive it hard. Folded regions
/// are stored as BYTE ranges (not line numbers) so edits above a fold shift
/// it correctly, and line spans are always derived fresh from the live
/// buffer, so post-edit line drift can never desync a cached line number.
public struct FoldModel: Equatable {
    /// Latest foldable regions from a parse, sorted by `range.lowerBound`
    /// ascending (ties broken by `range.upperBound` descending, so an outer
    /// region sorts before an inner region sharing the same start —
    /// `foldableRegion(atLine:)` relies on this to find the innermost match
    /// via `.last`).
    public private(set) var foldable: [FoldRange] = []
    /// Folded regions' full byte ranges, sorted by `lowerBound`.
    public private(set) var folded: [Range<ByteOffset>] = []
    /// `foldable`, indexed by `startLine`, rebuilt alongside it in
    /// `updateFoldable` — lets `gutterMark` answer in O(1) instead of a
    /// linear scan repeated on every ruler draw line (rulers redraw on
    /// every keystroke/selection change; a large file can have 10^5+ fold
    /// regions). Same "first wins" dedup as the array it replaces: since
    /// `foldable` is sorted by `range.lowerBound` ascending (ties broken by
    /// `range.upperBound` descending — see `foldable`'s doc comment), the
    /// first candidate reached for a given `startLine` while building this
    /// dictionary is the outermost/largest one, matching what
    /// `foldable.first(where:)` used to return.
    private var foldableByStartLine: [Int: FoldRange] = [:]

    public init() {}

    /// Latest foldable regions from a parse; reconciles the folded set.
    ///
    /// A folded region survives iff some new foldable region shares its
    /// `lowerBound` — and it adopts that region's (possibly refined)
    /// extent, since the region legally may have grown or shrunk between
    /// parses. Anything whose start vanished from the new parse is dropped.
    public mutating func updateFoldable(_ ranges: [FoldRange]) {
        foldable = ranges.sorted {
            $0.range.lowerBound != $1.range.lowerBound
                ? $0.range.lowerBound < $1.range.lowerBound
                : $0.range.upperBound > $1.range.upperBound
        }
        var byStartLine: [Int: FoldRange] = [:]
        for candidate in foldable where byStartLine[candidate.startLine] == nil {
            byStartLine[candidate.startLine] = candidate
        }
        foldableByStartLine = byStartLine
        var extentByStart: [ByteOffset: Range<ByteOffset>] = [:]
        for candidate in foldable where extentByStart[candidate.range.lowerBound] == nil {
            extentByStart[candidate.range.lowerBound] = candidate.range
        }
        folded = folded
            .compactMap { extentByStart[$0.lowerBound] }
            .sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Shifts anchors by the transaction's deltas; any folded region
    /// overlapping an edit is unfolded (its text changed). Edits are
    /// processed back-to-front (mirrors `TextBuffer.apply`): each edit's
    /// range is expressed in coordinates that are still valid for every
    /// not-yet-processed edit, all of which lie to its left.
    ///
    /// Boundary convention (pins the reference model in the property
    /// test): a folded region is unfolded iff the edit's range strictly
    /// overlaps its *open* interval — `edit.lowerBound < region.upperBound
    /// && edit.upperBound > region.lowerBound`. A pure insertion exactly at
    /// either boundary is therefore never an overlap (it fails one side of
    /// that test), so it falls through to the shift-or-unchanged branches
    /// below instead of unfolding — which is exactly the desired "insertion
    /// at a region's boundary never unfolds" rule, with no separate special
    /// case needed.
    public mutating func apply(_ transaction: EditTransaction) {
        for edit in transaction.edits.reversed() {
            let oldLength = edit.range.upperBound.value - edit.range.lowerBound.value
            let delta = edit.replacement.utf8Count - oldLength

            folded = folded.compactMap { region in
                if edit.range.lowerBound < region.upperBound, edit.range.upperBound > region.lowerBound {
                    return nil // strict overlap → text inside the fold changed → unfold
                }
                if edit.range.upperBound <= region.lowerBound {
                    return ByteOffset(region.lowerBound.value + delta) ..< ByteOffset(region.upperBound.value + delta)
                }
                return region // edit lies entirely after the region: unaffected
            }

            // Foldable candidates aren't state (they're replaced wholesale
            // by the next `updateFoldable`), so they're shifted but never
            // dropped on overlap — only their anchor byte range moves.
            foldable = foldable.map { candidate in
                guard edit.range.upperBound <= candidate.range.lowerBound else { return candidate }
                return FoldRange(
                    range: ByteOffset(candidate.range.lowerBound.value + delta)
                        ..< ByteOffset(candidate.range.upperBound.value + delta),
                    startLine: candidate.startLine, endLine: candidate.endLine, depth: candidate.depth,
                )
            }
        }
    }

    /// Innermost foldable region whose lines contain `line` (for gutter
    /// clicks and caret commands). nil if none.
    public func foldableRegion(atLine line: Int) -> FoldRange? {
        foldable.last { $0.startLine <= line && line <= $0.endLine }
    }

    public mutating func fold(_ region: FoldRange) {
        guard !folded.contains(region.range) else { return }
        folded.append(region.range)
        folded.sort { $0.lowerBound < $1.lowerBound }
    }

    /// Unfolds the region folded at exactly this start, if any.
    public mutating func unfold(startingAt start: ByteOffset) {
        folded.removeAll { $0.lowerBound == start }
    }

    /// Unfolds every folded region containing `offset` (goto/find rule).
    public mutating func unfoldEnclosing(_ offset: ByteOffset) {
        folded.removeAll { $0.lowerBound <= offset && offset < $0.upperBound }
    }

    public mutating func foldAll() {
        folded = foldable.map(\.range).sorted { $0.lowerBound < $1.lowerBound }
    }

    public mutating func unfoldAll() {
        folded = []
    }

    /// Spec "Fold Level N": folds every depth==n region, unfolds depth<n,
    /// leaves depth>n folded state unchanged.
    public mutating func foldLevel(_ level: Int) {
        let depthByStart = Dictionary(
            foldable.map { ($0.range.lowerBound, $0.depth) },
            uniquingKeysWith: { first, _ in first },
        )
        let keptDeeper = folded.filter { (depthByStart[$0.lowerBound] ?? 0) > level }
        let levelN = foldable.filter { $0.depth == level }.map(\.range)
        var seen: Set<ByteOffset> = []
        folded = (keptDeeper + levelN)
            .sorted { $0.lowerBound < $1.lowerBound }
            .filter { seen.insert($0.lowerBound).inserted }
    }

    /// True if `offset` lies strictly inside a folded region's hidden part
    /// (i.e. beyond the region's first line).
    public func isInsideHiddenText(_ offset: ByteOffset, in buffer: TextBuffer) -> Bool {
        let line = buffer.linePosition(of: offset).line
        return hiddenLineSpans(in: buffer).contains { $0.contains(line) }
    }

    /// 0-based end-exclusive line spans currently hidden, merged, derived
    /// from `folded` against the CURRENT buffer (lines computed fresh —
    /// never cached, so post-edit line drift can't desync). Feed straight
    /// into `TextKit2Engine.setHiddenLineSpans(_:)`.
    public func hiddenLineSpans(in buffer: TextBuffer) -> [Range<Int>] {
        // Hidden = the region's lines after its first, i.e.
        // startLine+1 ..< endLine+1 (end-exclusive).
        let spans: [Range<Int>] = folded.compactMap { range in
            guard range.upperBound <= ByteOffset(buffer.utf8Count) else { return nil }
            let start = buffer.linePosition(of: range.lowerBound).line + 1
            let end = buffer.linePosition(of: range.upperBound).line + 1
            guard end > start else { return nil }
            return start ..< end
        }.sorted { $0.lowerBound < $1.lowerBound }

        var merged: [Range<Int>] = []
        for span in spans {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// Gutter mark for a line: none / foldable / folded. `buffer` is
    /// accepted for symmetry with `hiddenLineSpans`/`isInsideHiddenText`
    /// (byte-range foldable state, line-based query) but isn't needed here
    /// — `foldable.startLine` is already the line-space anchor. O(1) via
    /// `foldableByStartLine` (see its doc comment).
    public func gutterMark(atLine line: Int, in _: TextBuffer) -> FoldGutterMark {
        guard let region = foldableByStartLine[line] else { return .none }
        return folded.contains(region.range) ? .folded : .foldable
    }

    /// Innermost folded region whose HIDDEN lines (its body, i.e. lines
    /// `startLine+1...endLine` — never its own visible first line) contain
    /// `line`. Used to reposition a caret a fold operation just buried
    /// inside hidden text back onto the folded region's visible first
    /// line (spec invariant: caret never lands inside hidden text).
    /// `folded` is sorted by `lowerBound` ascending, so — mirroring
    /// `foldableRegion(atLine:)` — the LAST match is the innermost.
    public func foldedRegionHidingLine(_ line: Int, in buffer: TextBuffer) -> Range<ByteOffset>? {
        folded.last { range in
            let startLine = buffer.linePosition(of: range.lowerBound).line
            let endLine = buffer.linePosition(of: range.upperBound).line
            return line > startLine && line <= endLine
        }
    }
}
