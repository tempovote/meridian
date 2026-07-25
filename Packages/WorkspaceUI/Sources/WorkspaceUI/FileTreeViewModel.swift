import AppKit
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

    public var canNavigateToParent: Bool {
        guard let rootURL else { return false }
        let parent = rootURL.deletingLastPathComponent()
        return parent.path != rootURL.path && FileManager.default.fileExists(atPath: parent.path)
    }

    public var parentDirectoryName: String {
        guard let rootURL, canNavigateToParent else { return "" }
        return rootURL.deletingLastPathComponent().lastPathComponent
    }

    public func navigateToParentDirectory() {
        guard let rootURL, canNavigateToParent else { return }
        let parent = rootURL.deletingLastPathComponent()
        logDebug("navigateToParentDirectory: requesting sandbox access to '\(parent.path)'")

        // App Sandbox requires explicit user grant for directories outside the
        // originally opened scope. Show NSOpenPanel pre-directed at the parent
        // so the user just presses Open once — no typing required.
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        panel.prompt = "Open"
        panel.message = "Grant access to \(parent.lastPathComponent) to browse its contents."

        if panel.runModal() == .OK, let grantedURL = panel.url {
            logDebug("navigateToParentDirectory: user granted '\(grantedURL.path)'")
            let accessing = grantedURL.startAccessingSecurityScopedResource()
            setRootURL(grantedURL)
            if accessing {
                // Keep resource active long enough for the initial load, then release.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    grantedURL.stopAccessingSecurityScopedResource()
                }
            }
        } else {
            logDebug("navigateToParentDirectory: user cancelled panel")
        }
    }

    public func setRootURL(_ url: URL) {
        var isDir: ObjCBool = false
        let isFile = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        let targetURL = isFile ? url.deletingLastPathComponent() : url
        logDebug("setRootURL input: '\(url.path)', resolved folder: '\(targetURL.path)'")
        rootURL = targetURL
        loadDirectory(targetURL)
    }

    public func loadDirectory(_ url: URL) {
        logDebug("loadDirectory starting for: '\(url.path)'")
        let items = fetchContents(of: url, depth: 0)
        logDebug("loadDirectory completed for '\(url.path)': found \(items.count) items")
        for (idx, item) in items.enumerated() {
            logDebug("  Item #\(idx + 1): '\(item.name)' (isDir: \(item.isDirectory))")
        }
        rootItems = items
    }

    public func selectItem(_ item: FileTreeItem) {
        logDebug("selectItem: '\(item.name)', isDirectory: \(item.isDirectory)")
        selectedURL = item.url
        if !item.isDirectory {
            onSelectFile?(item.url)
        }
    }

    private func fetchContents(of directoryURL: URL, depth: Int) -> [FileTreeItem] {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDir)
        guard exists else {
            logDebug("fetchContents FAILED: path does NOT exist on disk: '\(directoryURL.path)'")
            return []
        }
        guard isDir.boolValue else {
            logDebug("fetchContents FAILED: path is NOT a directory: '\(directoryURL.path)'")
            return []
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
            )
            let folderName = directoryURL.lastPathComponent
            logDebug("contentsOfDirectory SUCCESS for '\(folderName)': \(urls.count) URLs")
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
        } catch {
            logDebug("contentsOfDirectory ERROR for '\(directoryURL.path)': \(error)")
            return []
        }
    }
}

private func logDebug(_ message: String) {
    let line = "[FileTree Debug] \(message)\n"
    Swift.print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/meridian_debug.log")) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/meridian_debug.log"))
        }
    }
}
