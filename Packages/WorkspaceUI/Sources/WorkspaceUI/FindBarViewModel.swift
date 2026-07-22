import DocumentCore
import EditorUI
import Observation
import SearchKit

/// Drives Find & Replace search/navigation/replace state for one
/// `EditorViewModel`. Extracted out of `FindBarView` (rather than living
/// as private `@State` on the view, as it originally did) so
/// `MeridianDocument` can implement the `findNext:`/`findPrevious:`
/// responder-chain actions the View menu, Command Palette, and ⌘G/⇧⌘G all
/// dispatch — none of which can reach into a SwiftUI view's private state.
@MainActor
@Observable
public final class FindBarViewModel {
    private let editorViewModel: EditorViewModel
    private let searchEngine: SearchEngine

    public var query: String = ""
    public var replacement: String = ""
    public var isCaseSensitive = false
    public var isWholeWord = false
    public var isRegex = false
    public var isReplaceExpanded: Bool

    public private(set) var matches: [SearchMatch] = []
    public private(set) var currentMatchIndex: Int = 0

    public init(
        editorViewModel: EditorViewModel,
        searchEngine: SearchEngine = SearchEngine(),
        startExpanded: Bool = false,
    ) {
        self.editorViewModel = editorViewModel
        self.searchEngine = searchEngine
        isReplaceExpanded = startExpanded
    }

    /// Whether this instance was built for `editorViewModel` — lets a
    /// caller that keeps a `FindBarViewModel` alive across the Find bar
    /// being hidden (so ⌘G/⇧⌘G keep working with the bar closed) detect
    /// when it's stale, e.g. focus moved to a different split pane, and
    /// a fresh instance is needed instead of reusing this one.
    public func isBound(to editorViewModel: EditorViewModel) -> Bool {
        self.editorViewModel === editorViewModel
    }

    public var matchCountText: String {
        if query.isEmpty {
            return ""
        }
        if matches.isEmpty {
            return "No results"
        }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }

    private var options: SearchOptions {
        var opts: SearchOptions = []
        if isCaseSensitive {
            opts.insert(.caseSensitive)
        }
        if isWholeWord {
            opts.insert(.wholeWord)
        }
        if isRegex {
            opts.insert(.regularExpression)
        }
        return opts
    }

    public func performSearch() {
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
        matches = searchEngine.findAll(query: query, in: editorViewModel.buffer, options: options)
        if matches.isEmpty {
            currentMatchIndex = 0
        } else {
            currentMatchIndex = 0
            selectMatch(matches[0])
        }
    }

    public func findNext() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        selectMatch(matches[currentMatchIndex])
    }

    public func findPrevious() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        selectMatch(matches[currentMatchIndex])
    }

    public func replaceCurrent() {
        guard !matches.isEmpty, currentMatchIndex < matches.count else { return }
        let match = matches[currentMatchIndex]
        let tx = searchEngine.buildReplaceTransaction(
            matches: [match],
            replacement: replacement,
            in: editorViewModel.buffer,
            origin: .user,
        )
        editorViewModel.perform(tx)
        performSearch()
    }

    public func replaceAll() {
        guard !matches.isEmpty else { return }
        let tx = searchEngine.buildReplaceTransaction(
            matches: matches,
            replacement: replacement,
            in: editorViewModel.buffer,
            origin: .replaceAll,
        )
        editorViewModel.perform(tx)
        performSearch()
    }

    private func selectMatch(_ match: SearchMatch) {
        editorViewModel.setSelection(SelectionSet(ranges: [match.range]))
    }
}
