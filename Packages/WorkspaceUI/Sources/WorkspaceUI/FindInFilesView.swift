import SearchKit
import SwiftUI

/// Sidebar/Panel view for workspace-wide Find in Files search and results display.
@MainActor
public struct FindInFilesView: View {
    @Bindable var viewModel: FindInFilesViewModel
    @FocusState private var isQueryFocused: Bool

    public init(viewModel: FindInFilesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Search Inputs Section
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    Text("in \(viewModel.searchFolder?.lastPathComponent ?? "workspace")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(viewModel.searchFolder?.path ?? "")
                    Spacer()
                    Button("Choose Folder...") {
                        selectSearchFolder()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(.horizontal, 4)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search workspace...", text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .focused($isQueryFocused)
                        .onSubmit { viewModel.performSearch() }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                // Search Option Toggles
                HStack(spacing: 4) {
                    ToggleOptionButton(title: "Aa", isSelected: $viewModel.isCaseSensitive) {
                        viewModel.performSearch()
                    }
                    ToggleOptionButton(title: "W", isSelected: $viewModel.isWholeWord) {
                        viewModel.performSearch()
                    }
                    ToggleOptionButton(title: ".*", isSelected: $viewModel.isRegex) {
                        viewModel.performSearch()
                    }
                    Spacer()
                }

                // Filter Patterns (Includes / Excludes)
                HStack(spacing: 6) {
                    TextField("files to include (e.g. *.swift)", text: $viewModel.includePattern)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)

                    TextField("files to exclude (e.g. *.png)", text: $viewModel.excludePattern)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()

            // Status Bar
            HStack {
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)

            // Results List
            List {
                ForEach(viewModel.results) { result in
                    Section(header: FileHeaderView(fileURL: result.fileURL, count: result.matches.count)) {
                        ForEach(result.matches) { match in
                            MatchRowView(match: match, isSelected: viewModel.selectedMatchID == match.id) {
                                viewModel.selectMatch(match, in: result.fileURL)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .onAppear {
            isQueryFocused = true
        }
    }

    private func selectSearchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.searchFolder = url
        }
    }
}

private struct FileHeaderView: View {
    let fileURL: URL
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
            Text(fileURL.lastPathComponent)
                .font(.caption.bold())
                .foregroundColor(.primary)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}

private struct MatchRowView: View {
    let match: FileMatch
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(match.line):")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 28, alignment: .trailing)

                Text(match.lineSnippet)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
