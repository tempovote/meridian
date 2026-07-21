import AppKit

/// A fully pre-resolved (real `NSColor`, no further computation needed)
/// style for one semantic token type.
public struct ResolvedStyle: Sendable {
    public let color: NSColor
    public let bold: Bool
    public let italic: Bool
}

/// Fully pre-resolved editor-chrome colors.
public struct ResolvedEditorColors: Sendable {
    public let background: NSColor
    public let caret: NSColor
    public let lineHighlight: NSColor
}
