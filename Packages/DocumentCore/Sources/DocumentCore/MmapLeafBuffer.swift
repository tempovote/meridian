import Foundation

/// Memory-mapped file buffer wrapper enabling low-memory instant loading of huge files (≥ 64MB up to GB scale).
public final class MmapLeafBuffer: @unchecked Sendable {
    public let url: URL
    public let fileSize: Int
    private let mappedData: Data

    public init(url: URL) throws {
        self.url = url
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        fileSize = Int((attributes[.size] as? Int64) ?? 0)
        mappedData = try Data(contentsOf: url, options: .alwaysMapped)
    }

    /// Accesses bytes in a specified subrange without copying the entire file into memory.
    public func bytes(in range: Range<Int>) -> [UInt8] {
        let clampedStart = max(0, min(range.lowerBound, fileSize))
        let clampedEnd = max(clampedStart, min(range.upperBound, fileSize))
        guard clampedStart < clampedEnd else { return [] }
        return [UInt8](mappedData[clampedStart ..< clampedEnd])
    }

    /// Converts the mapped data into a `TextBuffer`.
    public func toTextBuffer() -> TextBuffer {
        TextBuffer(bytes: [UInt8](mappedData))
    }
}
