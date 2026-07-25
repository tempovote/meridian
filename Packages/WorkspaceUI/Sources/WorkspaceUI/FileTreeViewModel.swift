import Foundation

/// Manages directory listing and file selection state for the workspace file sidebar.
@MainActor
public final class FileTreeViewModel: ObservableObject {
    @Published public var rootURL: URL?
    @Published public var rootItems: [FileTreeItem] = []
    @Published public var selectedURL: URL?

    public var onSelectFile: ((URL) -> Void)?
    public var onToggleSidebar: (() -> Void)?

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL
        if let rootURL {
            loadDirectory(rootURL)
        }
    }

    public func setRootURL(_ url: URL) {
        var isDir: ObjCBool = false
        let isFile = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        let targetURL = isFile ? url.deletingLastPathComponent() : url
        Swift.print("[FileTree Debug] setRootURL input: \(url.path), resolved folder: \(targetURL.path)")
        rootURL = targetURL
        loadDirectory(targetURL)
    }

    public func loadDirectory(_ url: URL) {
        let items = fetchContents(of: url, depth: 0)
        Swift.print("[FileTree Debug] Loaded \(items.count) root items for: \(url.path)")
        rootItems = items
    }

    public func selectItem(_ item: FileTreeItem) {
        Swift.print("[FileTree Debug] selectItem: \(item.name), isDirectory: \(item.isDirectory)")
        selectedURL = item.url
        if !item.isDirectory {
            onSelectFile?(item.url)
        }
    }

    private func fetchContents(of directoryURL: URL, depth: Int) -> [FileTreeItem] {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            Swift.print("[FileTree Debug] fetchContents skipped non-directory: \(directoryURL.path)")
            return []
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
        ) else {
            Swift.print("[FileTree Debug] contentsOfDirectory returned nil for: \(directoryURL.path)")
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
            let children: [FileTreeItem]? = (isDir && depth < 1) ? fetchContents(of: url, depth: depth + 1) : nil
            return FileTreeItem(url: url, isDirectory: isDir, children: children)
        }
    }
}
