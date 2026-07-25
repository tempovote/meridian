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

    /// Converts the mapped data into a `TextBuffer` without copying the raw file into an intermediate heap array.
    public func toTextBuffer() -> TextBuffer {
        let node = mappedData.withUnsafeBytes { rawBuffer -> Node in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Node.leaf(Leaf(bytes: []))
            }
            let bufferPtr = UnsafeBufferPointer(start: baseAddress, count: rawBuffer.count)
            return Node.build(from: bufferPtr)
        }
        return TextBuffer(root: node)
    }
}
