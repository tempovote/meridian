import Foundation

/// Represents a single 16-byte row in a hex dump.
public struct HexRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public let offset: Int
    public let offsetString: String
    public let hexBytes: String
    public let ascii: String

    public init(offset: Int, offsetString: String, hexBytes: String, ascii: String) {
        id = offset
        self.offset = offset
        self.offsetString = offsetString
        self.hexBytes = hexBytes
        self.ascii = ascii
    }
}

/// Formatter that converts binary Data into offset-aligned hex rows.
public enum HexFormatter {
    public static func format(data: Data, bytesPerRow: Int = 16) -> [HexRow] {
        guard !data.isEmpty else { return [] }
        var rows: [HexRow] = []
        let totalCount = data.count

        for rowOffset in stride(from: 0, to: totalCount, by: bytesPerRow) {
            let chunkEnd = min(rowOffset + bytesPerRow, totalCount)
            let chunk = data[rowOffset ..< chunkEnd]

            let offsetStr = String(format: "%08X", rowOffset)
            let (hexBytesStr, asciiStr) = formatChunk(chunk: chunk, bytesPerRow: bytesPerRow)

            rows.append(
                HexRow(
                    offset: rowOffset,
                    offsetString: offsetStr,
                    hexBytes: hexBytesStr,
                    ascii: asciiStr,
                ),
            )
        }
        return rows
    }

    private static func formatChunk(chunk: Data.SubSequence, bytesPerRow: Int) -> (hexBytes: String, ascii: String) {
        var hexParts: [String] = []
        var asciiChars: [Character] = []

        for (byteIndex, byteValue) in chunk.enumerated() {
            hexParts.append(String(format: "%02X", byteValue))
            if byteValue >= 32, byteValue <= 126 {
                asciiChars.append(Character(UnicodeScalar(byteValue)))
            } else {
                asciiChars.append(".")
            }

            if byteIndex == 7, chunk.count > 8 {
                hexParts.append(" ")
            }
        }

        if chunk.count < bytesPerRow {
            let missingBytes = bytesPerRow - chunk.count
            for missingIndex in 0 ..< missingBytes {
                hexParts.append("  ")
                if (chunk.count + missingIndex) == 7 {
                    hexParts.append(" ")
                }
            }
        }

        return (hexParts.joined(separator: " "), String(asciiChars))
    }
}
