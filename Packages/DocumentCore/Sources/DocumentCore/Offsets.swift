/// Byte offset into the buffer's UTF-8 storage. Rope-native and tree-sitter-native.
/// Must always land on a Unicode scalar boundary when used in public APIs.
public struct ByteOffset: Hashable, Comparable, Sendable {
    /// The raw byte offset.
    public var value: Int

    /// Creates a byte offset from a raw value.
    public init(_ value: Int) {
        self.value = value
    }

    /// Orders offsets by their raw value.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

/// Offset in UTF-16 code units. TextKit 2 / NSRange native.
public struct UTF16Offset: Hashable, Comparable, Sendable {
    /// The raw UTF-16 code-unit offset.
    public var value: Int

    /// Creates a UTF-16 offset from a raw value.
    public init(_ value: Int) {
        self.value = value
    }

    /// Orders offsets by their raw value.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

/// Line/column position. Lines are zero-based; the column is measured in
/// UTF-16 code units from the start of the line (TextKit convention).
public struct LinePosition: Hashable, Sendable {
    /// The zero-based line number.
    public var line: Int
    /// The column, in UTF-16 code units from the start of the line.
    public var utf16Column: Int

    /// Creates a line/column position.
    public init(line: Int, utf16Column: Int) {
        self.line = line
        self.utf16Column = utf16Column
    }
}
