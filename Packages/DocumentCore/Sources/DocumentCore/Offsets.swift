/// Byte offset into the buffer's UTF-8 storage. Rope-native and tree-sitter-native.
/// Must always land on a Unicode scalar boundary when used in public APIs.
public struct ByteOffset: Hashable, Comparable, Sendable {
    public var value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

/// Offset in UTF-16 code units. TextKit 2 / NSRange native.
public struct UTF16Offset: Hashable, Comparable, Sendable {
    public var value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

/// Line/column position. Lines are zero-based; the column is measured in
/// UTF-16 code units from the start of the line (TextKit convention).
public struct LinePosition: Hashable, Sendable {
    public var line: Int
    public var utf16Column: Int

    public init(line: Int, utf16Column: Int) {
        self.line = line
        self.utf16Column = utf16Column
    }
}
