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
        VStack(alignment: .leading, spacing: 6) {
            // Search Input Field
            HStack(spacing: 8) {
                Image("icon_command_palette")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundColor(.accentColor)
                TextField("Type a command…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFieldFocused)
                    .onSubmit(execute)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)

            // Results List
            if !viewModel.filteredCommands.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(viewModel.filteredCommands.enumerated()), id: \.element.id) { index, command in
                                commandRow(command, isSelected: index == viewModel.selectedIndex, index: index)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex)
                    }
                }
            } else {
                Text("No matching commands")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(10)
        .background(Material.ultraThick)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 7)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFieldFocused = true
            }
        }
    }

    private func commandRow(_ command: Command, isSelected: Bool, index: Int) -> some View {
        HStack {
            Text(command.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))
            Spacer()
            if let keyEquivalent = command.keyEquivalent, !keyEquivalent.isEmpty {
                Text(Self.shortcutDisplayString(modifierMask: command.modifierMask, keyEquivalent: keyEquivalent))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .cornerRadius(5)
        .onHover { isHovered in
            if isHovered {
                viewModel.moveSelection(by: index - viewModel.selectedIndex)
            }
        }
        .onTapGesture {
            selectAndExecute(at: index)
        }
    }

    private func selectAndExecute(at index: Int) {
        let delta = index - viewModel.selectedIndex
        viewModel.moveSelection(by: delta)
        execute()
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
    static func shortcutDisplayString(modifierMask: NSEvent.ModifierFlags, keyEquivalent: String) -> String {
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
        let keyGlyph: String = switch keyEquivalent {
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): "→"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓"
        default: keyEquivalent.uppercased()
        }
        return glyphs + keyGlyph
    }
}
