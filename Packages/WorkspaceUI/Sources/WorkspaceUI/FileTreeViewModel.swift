import Foundation

/// Manages directory listing and file selection state for the workspace file sidebar.
@MainActor
public final class FileTreeViewModel: ObservableObject {
    @Published public var rootURL: URL?
    @Published public var rootItems: [FileTreeItem] = []
    @Published public var selectedURL: URL?

    public var onSelectFile: ((URL) -> Void)?

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL
        if let rootURL {
            loadDirectory(rootURL)
        }
    }

    public func setRootURL(_ url: URL) {
        rootURL = url
        loadDirectory(url)
    }

    public func loadDirectory(_ url: URL) {
        let items = fetchContents(of: url)
        rootItems = items
    }

    public func selectItem(_ item: FileTreeItem) {
        selectedURL = item.url
        if !item.isDirectory {
            onSelectFile?(item.url)
        }
    }

    private func fetchContents(of directoryURL: URL) -> [FileTreeItem] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }

        let sorted = urls.sorted { first, second in
            let firstIsDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let secondIsDir = (try? second.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if firstIsDir != secondIsDir {
                return firstIsDir && !secondIsDir
            }
            return first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedAscending
        }

        return sorted.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let children: [FileTreeItem]? = isDir ? fetchContents(of: url) : nil
            return FileTreeItem(url: url, isDirectory: isDir, children: children)
        }
    }
}
