import Foundation
import Observation
import SearchKit

/// ViewModel managing state and execution for workspace-wide Find in Files.
@MainActor
@Observable
public final class FindInFilesViewModel {
    public var query: String = "" {
        didSet { scheduleSearch() }
    }

    public var replacement: String = ""
    public var isCaseSensitive: Bool = false {
        didSet { scheduleSearch() }
    }

    public var isWholeWord: Bool = false {
        didSet { scheduleSearch() }
    }

    public var isRegex: Bool = false {
        didSet { scheduleSearch() }
    }

    public var includePattern: String = "" {
        didSet { scheduleSearch() }
    }

    public var excludePattern: String = "" {
        didSet { scheduleSearch() }
    }

    public var searchFolder: URL? {
        didSet { performSearch() }
    }

    public private(set) var results: [FileSearchResult] = []
    public private(set) var isSearching: Bool = false
    public var selectedMatchID: String?

    public var onSelectMatch: ((URL, FileMatch) -> Void)?

    private let engine = FindInFilesEngine()
    private var searchTask: Task<Void, Never>?

    public init(searchFolder: URL? = nil) {
        if let searchFolder {
            self.searchFolder = searchFolder
        } else {
            let pwd = FileManager.default.currentDirectoryPath
            self.searchFolder = pwd.isEmpty ? URL(fileURLWithPath: NSHomeDirectory()) : URL(fileURLWithPath: pwd)
        }
    }

    public var totalMatchesCount: Int {
        results.reduce(0) { $0 + $1.matches.count }
    }

    public var totalFilesCount: Int {
        results.count
    }

    public var statusText: String {
        if isSearching {
            return "Searching..."
        }
        if query.isEmpty {
            return "Type a search query"
        }
        if results.isEmpty {
            return "No results found"
        }
        let matchWord = totalMatchesCount == 1 ? "match" : "matches"
        let fileWord = totalFilesCount == 1 ? "file" : "files"
        return "\(totalMatchesCount) \(matchWord) in \(totalFilesCount) \(fileWord)"
    }

    public func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            if !Task.isCancelled {
                self.performSearch()
            }
        }
    }

    public func performSearch() {
        searchTask?.cancel()
        guard !query.isEmpty, let searchFolder else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        var options: SearchOptions = []
        if isCaseSensitive {
            options.insert(.caseSensitive)
        }
        if isWholeWord {
            options.insert(.wholeWord)
        }
        if isRegex {
            options.insert(.regularExpression)
        }

        let searchQuery = FindInFilesQuery(
            query: query,
            replacement: replacement,
            searchFolder: searchFolder,
            options: options,
            includePattern: includePattern,
            excludePattern: excludePattern,
        )

        searchTask = Task {
            let found = await engine.search(query: searchQuery)
            if !Task.isCancelled {
                self.results = found
                self.isSearching = false
            }
        }
    }

    public func selectMatch(_ match: FileMatch, in fileURL: URL) {
        selectedMatchID = match.id
        onSelectMatch?(fileURL, match)
    }
}
