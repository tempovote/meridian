import Observation

/// Drives the Command Palette's search field and result list. Takes an
/// explicit `commands` list at construction (rather than reading
/// `CommandRegistry.commands` itself) so it stays independently testable
/// without requiring `MainMenu.build()` to have run first.
@MainActor
@Observable
public final class CommandPaletteViewModel {
    private let commands: [Command]
    public var query: String = "" {
        didSet {
            // Clamp selectedIndex to the bounds of the new filtered list
            let count = filteredCommands.count
            if count > 0 {
                selectedIndex = min(selectedIndex, count - 1)
            } else {
                selectedIndex = 0
            }
        }
    }

    public private(set) var selectedIndex: Int = 0

    public init(commands: [Command]) {
        self.commands = commands
    }

    public var filteredCommands: [Command] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.title.range(of: query, options: .caseInsensitive) != nil }
    }

    public var selectedCommand: Command? {
        let filtered = filteredCommands
        guard filtered.indices.contains(selectedIndex) else { return nil }
        return filtered[selectedIndex]
    }

    public func moveSelection(by delta: Int) {
        let count = filteredCommands.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }
}
