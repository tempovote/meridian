import AppKit
import DocumentCore
import SyntaxKit

extension TextKit2Engine {
    /// Kicks off a background reparse + repaint for the current buffer.
    /// Fire-and-forget: discards the result if `buffer.version` has
    /// already moved on by the time the actor call returns (stale-result
    /// drop, ARCHITECTURE §3.4), or if `loadGeneration` has advanced —
    /// i.e. `load(buffer:)` adopted an entirely different buffer lineage
    /// in the meantime (e.g. an `NSDocument` revert), which could
    /// otherwise share the stale request's version number by coincidence
    /// since `TextBuffer.version` resets to 0 on every new instance.
    func highlightCurrentBuffer() {
        guard let languageID else { return }
        let snapshot = buffer
        let requestedVersion = snapshot.version
        let requestedGeneration = loadGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let runs: [TokenRun]
            do {
                runs = try await syntaxService.reparse(
                    documentID: syntaxDocumentID,
                    languageID: languageID,
                    snapshot: snapshot,
                    version: requestedVersion,
                    edit: nil,
                )
            } catch {
                return
            }
            guard loadGeneration == requestedGeneration,
                  buffer.version == requestedVersion
            else { return }
            applyHighlighting(runs, against: snapshot)
        }
    }

    func applyHighlighting(_ runs: [TokenRun], against snapshot: TextBuffer) {
        lastTokenRuns = runs
        isMirroring = true
        defer { isMirroring = false }
        contentStorage.performEditingTransaction {
            for run in runs {
                let style = themeEngine.resolvedStyle(for: run.type.rawValue)
                let location = snapshot.utf16Offset(of: run.range.lowerBound).value
                let length = snapshot.utf16Offset(of: run.range.upperBound).value - location
                guard location >= 0, length >= 0, location + length <= storage.length else { continue }
                let range = NSRange(location: location, length: length)
                storage.addAttribute(.foregroundColor, value: style.color, range: range)
                storage.addAttribute(.font, value: fontCache.font(bold: style.bold, italic: style.italic), range: range)
            }
        }
        updateBracketHighlight()
    }

    /// Recomputes and repaints the bracket-match highlight from the
    /// current caret position. Always clears any previously painted pair
    /// first — a stale highlight must never survive a caret move that no
    /// longer finds a match.
    func updateBracketHighlight() {
        for range in currentBracketHighlightRanges where range.location + range.length <= storage.length {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        currentBracketHighlightRanges = []

        // `buffer` (the rope mirror) is only advanced by `buffer.apply(...)`
        // *after* `performEditingTransaction`'s closure returns, but AppKit
        // can fire `textViewDidChangeSelection` synchronously as a side
        // effect of `storage.replaceCharacters` itself — mid-transaction,
        // while `buffer` still holds the pre-edit content but `storage`/
        // `textView.selectedRanges` already reflect the post-edit content.
        // `storage.length` is always current, so a length mismatch is a
        // reliable, cheap signal that `buffer` is momentarily stale; skip
        // this recomputation and let the caller that eventually re-syncs
        // `buffer` (`apply`/`handleUserEdit`, both of which call
        // `highlightCurrentBuffer()` → `applyHighlighting` →
        // `updateBracketHighlight()` again once consistent) repaint it.
        guard storage.length == buffer.utf16Count else { return }

        let selectedRanges = textView.selectedRanges.map(\.rangeValue)
        guard selectedRanges.count == 1, let selected = selectedRanges.first, selected.length == 0,
              selected.location <= buffer.utf16Count
        else { return }
        let caret = buffer.byteOffset(of: UTF16Offset(selected.location))
        guard let match = BracketMatcher.match(in: buffer, at: caret, tokenRuns: lastTokenRuns) else { return }

        let color = themeEngine.editorColors.bracketMatch
        for offset in [match.open, match.close] {
            let location = buffer.utf16Offset(of: offset).value
            guard location < storage.length else { continue }
            let range = NSRange(location: location, length: 1)
            storage.addAttribute(.backgroundColor, value: color, range: range)
            currentBracketHighlightRanges.append(range)
        }
    }
}
