import DocumentCore
import Foundation

/// A text file decoded into the editor's internal model, plus the on-disk
/// metadata needed to save it back faithfully and to run open-time guards.
public struct LoadedTextFile: Sendable {
    /// The decoded content, at version 0.
    public let buffer: TextBuffer
    /// The detected on-disk encoding — what save re-encodes to.
    public let encoding: TextEncoding
    /// True iff the file began with a byte-order mark (re-emitted on save).
    public let hadBOM: Bool
    /// True iff any U+FFFD substitution was made while decoding.
    public let repairsMade: Bool
    /// The most common line-break style, or nil for files with no breaks.
    public let dominantLineEnding: LineEnding?
    /// The file's size on disk, in bytes.
    public let byteSize: Int
    /// The longest line's length in UTF-8 bytes, excluding break characters.
    /// Drives the pathological-line-shape guard (ADR 0009).
    public let longestLineUTF8Length: Int
}

/// Errors thrown by FileKit's text-file I/O. Typed per project convention.
public enum FileKitError: Error {
    /// The file could not be read from disk.
    case unreadable(url: URL, underlying: any Error)
    /// The file could not be written to disk.
    case unwritable(url: URL, underlying: any Error)
    /// A legacy encoding cannot represent the buffer's content losslessly.
    case unencodable(encoding: TextEncoding)
}

/// Synchronous text-file loading and saving (P1 scope: files are small —
/// the ≥ 64 MB guard rejects before this code runs on anything huge).
public enum TextFileIO {
    /// Reads and decodes the file at `url`, computing save-fidelity and
    /// guard metadata. Never interprets content — every byte sequence
    /// decodes (DocumentCore §6.4 total pipeline).
    public static func loadTextFile(at url: URL) throws -> LoadedTextFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FileKitError.unreadable(url: url, underlying: error)
        }
        let decoded = TextDecoder.decode(ArraySlice([UInt8](data)))
        return LoadedTextFile(
            buffer: decoded.buffer,
            encoding: decoded.encoding,
            hadBOM: decoded.hadBOM,
            repairsMade: decoded.repairsMade,
            dominantLineEnding: decoded.buffer.lineEndingStats().dominant,
            byteSize: data.count,
            longestLineUTF8Length: longestLineUTF8Length(of: decoded.buffer),
        )
    }

    /// Encodes `buffer` for on-disk storage in `encoding`.
    ///
    /// - Throws: ``FileKitError/unencodable(encoding:)`` when a legacy
    ///   encoding cannot represent the content losslessly.
    public static func encode(
        _ buffer: TextBuffer, as encoding: TextEncoding, includeBOM: Bool,
    ) throws -> Data {
        guard let bytes = encoding.encode(buffer.string, includeBOM: includeBOM) else {
            throw FileKitError.unencodable(encoding: encoding)
        }
        return Data(bytes)
    }

    /// Encodes and writes `buffer` to `url` atomically (write-to-temp +
    /// rename — a crash mid-save never leaves a truncated file).
    public static func saveTextFile(
        _ buffer: TextBuffer, as encoding: TextEncoding, includeBOM: Bool, to url: URL,
    ) throws {
        let data = try encode(buffer, as: encoding, includeBOM: includeBOM)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw FileKitError.unwritable(url: url, underlying: error)
        }
    }

    /// One O(n) chunk-wise pass; line length counts bytes strictly between
    /// breaks (CR, LF, and CRLF all terminate; break bytes never counted).
    /// Byte-level scanning is safe: UTF-8 continuation bytes are ≥ 0x80,
    /// so every 0x0A/0x0D byte is a genuine break character.
    static func longestLineUTF8Length(of buffer: TextBuffer) -> Int {
        var longest = 0
        var current = 0
        for chunk in buffer.chunks() {
            for byte in chunk.bytes {
                if byte == 0x0A || byte == 0x0D {
                    longest = max(longest, current)
                    current = 0
                } else {
                    current += 1
                }
            }
        }
        return max(longest, current)
    }
}
