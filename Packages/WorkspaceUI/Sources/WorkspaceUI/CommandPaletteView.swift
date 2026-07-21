import AppKit
import SwiftUI

/// Floating command search overlay, presented the same way `FindBarView`
/// is (an `NSHostingView` inserted at the top of the document window's
/// container stack) — not a separate window.
public struct CommandPaletteView: View {
    @Bindable var viewModel: CommandPaletteViewModel
    public let onExecute: () -> Void
    public let onClose: () -> Void
    /// Claims SwiftUI-level keyboard focus for the search field as soon as
    /// the palette appears. `window.makeFirstResponder(host)` (in
    /// `MeridianDocument.showCommandPalette(_:)`) only makes the enclosing
    /// `NSHostingView` the AppKit first responder — that does not, by
    /// itself, give any SwiftUI view inside it keyboard focus, so without
    /// this the `.onKeyPress` handlers below (and the `TextField`) stay
    /// unresponsive until the user clicks in.
    @FocusState private var isSearchFieldFocused: Bool

    public init(viewModel: CommandPaletteViewModel, onExecute: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onExecute = onExecute
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Type a command…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit(execute)
            }

            if !viewModel.filteredCommands.isEmpty {
                Divider()
                ForEach(Array(viewModel.filteredCommands.enumerated()), id: \.element.id) { index, command in
                    commandRow(command, isSelected: index == viewModel.selectedIndex)
                        .onTapGesture {
                            viewModel.moveSelection(by: index - viewModel.selectedIndex)
                            execute()
                        }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Material.bar)
        .cornerRadius(6)
        .shadow(radius: 2)
        .padding(8)
        .frame(width: 420)
        .onKeyPress(.upArrow) {
            viewModel.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    private func commandRow(_ command: Command, isSelected: Bool) -> some View {
        HStack {
            Text(command.title)
            Spacer()
            if let keyEquivalent = command.keyEquivalent, !keyEquivalent.isEmpty {
                Text(keyEquivalent.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }

    private func execute() {
        guard viewModel.selectedCommand != nil else { return }
        onExecute()
    }
}
