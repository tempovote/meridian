import AppKit
import Testing
@testable import WorkspaceUI

@MainActor
@Suite("CommandPaletteViewModelTests")
struct CommandPaletteViewModelTests {
    private let sample: [Command] = [
        Command(title: "Open File", selector: Selector(("openFile:")), keyEquivalent: "o"),
        Command(title: "Save", selector: Selector(("save:")), keyEquivalent: "s"),
        Command(title: "Find and Replace", selector: Selector(("findReplace:")), keyEquivalent: nil),
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
}
