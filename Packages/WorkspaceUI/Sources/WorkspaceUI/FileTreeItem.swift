import Foundation

/// Represents a single file or directory node in the workspace file tree.
public struct FileTreeItem: Identifiable, Hashable, Sendable {
    public var id: URL {
        url
    }

    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var children: [FileTreeItem]?

    public init(url: URL, isDirectory: Bool, children: [FileTreeItem]? = nil) {
        self.url = url
        name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = children
    }
}
