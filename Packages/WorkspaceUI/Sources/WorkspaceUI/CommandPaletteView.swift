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
                Text(Self.shortcutDisplayString(modifierMask: command.modifierMask, keyEquivalent: keyEquivalent))
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

    /// Renders a shortcut the same way macOS menus do: modifier glyphs in
    /// the conventional ⌃⌥⇧⌘ order, then the key. Without the modifier
    /// glyphs, commands that share a key but differ in modifiers (Find ⌘F
    /// vs. Find and Replace ⌘⌥F, Split Horizontally ⌘\ vs. Split
    /// Vertically ⌘⇧\) render identically and look like duplicates.
    ///
    /// An uppercase letter key equivalent (e.g. Find Previous's `"G"`,
    /// vs. Find Next's `"g"`) implicitly requires Shift in AppKit even
    /// when `keyEquivalentModifierMask` itself omits `.shift` — matching
    /// `MainMenu.swift`'s convention of expressing Shift via case rather
    /// than an explicit modifier for menu items that don't otherwise need
    /// a custom mask. Uppercasing the key for display without accounting
    /// for this would make Find Next and Find Previous both read "⌘G".
    private static func shortcutDisplayString(modifierMask: NSEvent.ModifierFlags, keyEquivalent: String) -> String {
        let impliesShift = keyEquivalent != keyEquivalent.lowercased()
        var glyphs = ""
        if modifierMask.contains(.control) {
            glyphs += "⌃"
        }
        if modifierMask.contains(.option) {
            glyphs += "⌥"
        }
        if modifierMask.contains(.shift) || impliesShift {
            glyphs += "⇧"
        }
        if modifierMask.contains(.command) {
            glyphs += "⌘"
        }
        return glyphs + keyEquivalent.uppercased()
    }
}
