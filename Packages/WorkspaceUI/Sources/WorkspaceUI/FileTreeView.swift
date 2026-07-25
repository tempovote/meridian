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
        HStack(spacing: 6) {
            Button {
                viewModel.navigateToParentDirectory()
            } label: {
                Image(systemName: "arrow.up.folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(viewModel.canNavigateToParent ? .primary : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canNavigateToParent)
            .help("Go up to parent directory")

            Image(systemName: "folder")
                .foregroundColor(.secondary)
                .font(.system(size: 11))

            Text(viewModel.rootURL?.lastPathComponent.uppercased() ?? "WORKSPACE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                viewModel.onToggleSidebar?()
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar (⌘B)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Folder Opened")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text("Open a folder to view all workspace files and subdirectories.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("Open Folder…") {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                if openPanel.runModal() == .OK, let selectedFolder = openPanel.url {
                    viewModel.setRootURL(selectedFolder)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

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
