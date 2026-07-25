import SwiftUI

/// Sidebar SwiftUI view displaying a collapsible tree of files and directories in the workspace.
public struct FileTreeView: View {
    @ObservedObject public var viewModel: FileTreeViewModel

    public init(viewModel: FileTreeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()

            if viewModel.rootItems.isEmpty {
                emptyView
            } else {
                List(viewModel.rootItems, children: \.children) { item in
                    treeRow(item: item)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            Text(viewModel.rootURL?.lastPathComponent ?? "NO FOLDER OPEN")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No Folder Opened")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func treeRow(item: FileTreeItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: itemIconName(for: item))
                .foregroundColor(item.isDirectory ? .accentColor : .secondary)
                .font(.system(size: 12))

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectItem(item)
        }
    }

    private func itemIconName(for item: FileTreeItem) -> String {
        if item.isDirectory {
            return "folder.fill"
        }
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "swift":
            return "swift"
        case "json", "yml", "yaml", "plist", "toml":
            return "gearshape"
        case "md", "txt":
            return "doc.text"
        default:
            return "doc"
        }
    }
}
