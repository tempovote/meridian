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

            if !viewModel.favorites.isEmpty {
                favoritesSection
                Divider()
            }

            if viewModel.canNavigateToParent {
                parentFolderRow
                Divider()
            }

            if viewModel.rootItems.isEmpty {
                emptyView
            } else {
                List(viewModel.rootItems, children: \.children) { item in
                    treeRow(item: item)
                        .contextMenu {
                            fileContextMenu(url: item.url)
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 6) {
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Sidebar (⌘B)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FAVORITES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(viewModel.favorites, id: \.self) { url in
                favoriteRow(url: url)
            }
            .padding(.bottom, 4)
        }
    }

    private func favoriteRow(url: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: url))
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            Button {
                viewModel.removeFavorite(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from Favorites")
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.onOpenFavorite?(url)
        }
        .contextMenu {
            Button("Remove from Favorites") {
                viewModel.removeFavorite(url)
            }
        }
    }

    // MARK: - Parent Folder Row

    private var parentFolderRow: some View {
        Button {
            viewModel.navigateToParentDirectory()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(".. (\(viewModel.parentDirectoryName))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go up to parent directory: \(viewModel.parentDirectoryName)")
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Empty State

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

    // MARK: - File Tree Row

    private func treeRow(item: FileTreeItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: itemIconName(for: item))
                .foregroundColor(item.isDirectory ? .accentColor : .secondary)
                .font(.system(size: 12))

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            if !item.isDirectory, viewModel.isFavorite(item.url) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.yellow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectItem(item)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func fileContextMenu(url: URL) -> some View {
        let isFav = viewModel.isFavorite(url)
        if isFav {
            Button("Remove from Favorites") {
                viewModel.removeFavorite(url)
            }
        } else {
            Button("Add to Favorites") {
                viewModel.addFavorite(url)
            }
        }
    }

    // MARK: - Helpers

    private func itemIconName(for item: FileTreeItem) -> String {
        if item.isDirectory {
            return "folder.fill"
        }
        return iconName(for: item.url)
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
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
