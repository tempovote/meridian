import AppKit
import Testing
@testable import WorkspaceUI

@MainActor
@Suite("CommandPaletteViewModelTests")
struct CommandPaletteViewModelTests {
    /// These are synthetic fixture selectors, not real @objc methods —
    /// `#selector` requires an actual declaration to reference, so it can't
    /// express these. `NSSelectorFromString` builds a `Selector` from an
    /// arbitrary string at runtime without tripping the compiler's
    /// "use #selector instead of explicitly constructing a Selector"
    /// warning-as-error, which only fires for the `Selector(_:)` initializer.
    private let sample: [Command] = [
        Command(title: "Open File", selector: NSSelectorFromString("openFile:"), keyEquivalent: "o"),
        Command(title: "Save", selector: NSSelectorFromString("save:"), keyEquivalent: "s"),
        Command(title: "Find and Replace", selector: NSSelectorFromString("findReplace:"), keyEquivalent: nil),
    ]

    @Test func emptyQueryShowsAllCommandsInOrder() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        #expect(viewModel.filteredCommands.map(\.title) == ["Open File", "Save", "Find and Replace"])
    }

    @Test func filterIsCaseInsensitiveSubstring() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.query = "fin"
        #expect(viewModel.filteredCommands.map(\.title) == ["Find and Replace"])
    }

    @Test func filterWithNoMatchesReturnsEmpty() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.query = "zzz"
        #expect(viewModel.filteredCommands.isEmpty)
    }

    @Test func selectedIndexClampsAtUpperBound() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.moveSelection(by: 100)
        #expect(viewModel.selectedIndex == sample.count - 1)
    }

    @Test func selectedIndexClampsAtLowerBound() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.moveSelection(by: -100)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func selectedCommandTracksSelectedIndex() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.moveSelection(by: 1)
        #expect(viewModel.selectedCommand?.title == "Save")
    }

    @Test func selectedCommandIsNilWhenFilteredListIsEmpty() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.query = "zzz"
        #expect(viewModel.selectedCommand == nil)
    }

    @Test func narrowingQueryClampsSelectedIndexToNewBounds() {
        let viewModel = CommandPaletteViewModel(commands: sample)
        viewModel.moveSelection(by: 2) // selectedIndex == 2, "Find and Replace"
        viewModel.query = "sa" // only "Save" matches now — 1 item
        #expect(viewModel.selectedIndex == 0)
        #expect(viewModel.selectedCommand?.title == "Save")
    }

    @Test func shortcutDisplayStringMapsArrowFunctionKeysToGlyphs() throws {
        let leftArrow = try String(#require(UnicodeScalar(NSLeftArrowFunctionKey)))
        let rightArrow = try String(#require(UnicodeScalar(NSRightArrowFunctionKey)))
        #expect(CommandPaletteView
            .shortcutDisplayString(modifierMask: [.command, .option], keyEquivalent: leftArrow) == "⌥⌘←")
        #expect(CommandPaletteView.shortcutDisplayString(
            modifierMask: [.command, .option, .shift],
            keyEquivalent: rightArrow,
        ) == "⌥⇧⌘→")
    }
}
