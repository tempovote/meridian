import Foundation

/// A line-break style. Raw value is the break's literal characters.
public enum LineEnding: String, Hashable, Sendable, CaseIterable {
    /// Line feed (`\n`) — Unix/macOS convention.
    case lf = "\n"
    /// Carriage return + line feed (`\r\n`) — Windows convention.
    case crlf = "\r\n"
    /// Carriage return (`\r`) — classic Mac OS convention.
    case cr = "\r"
}

/// Counts of each line-break style in a buffer. A CRLF pair counts once as
/// `crlf` — never additionally as `cr` or `lf`.
public struct LineEndingStats: Hashable, Sendable {
    /// The number of LF (`\n`) line breaks in the buffer.
    public let lfCount: Int
    /// The number of CRLF (`\r\n`) line-break pairs in the buffer.
    public let crlfCount: Int
    /// The number of CR (`\r`) line breaks in the buffer (not part of CRLF pairs).
    public let crCount: Int

    /// Creates a line-ending statistics object from counts.
    ///
    /// - Parameters:
    ///   - lfCount: The number of LF (`\n`) line breaks.
    ///   - crlfCount: The number of CRLF (`\r\n`) pairs.
    ///   - crCount: The number of CR (`\r`) breaks not part of CRLF pairs.
    public init(lfCount: Int, crlfCount: Int, crCount: Int) {
        self.lfCount = lfCount
        self.crlfCount = crlfCount
        self.crCount = crCount
    }

    /// The most frequent style; ties prefer lf, then crlf, then cr
    /// (macOS-native wins). Nil when the buffer contains no line breaks.
    public var dominant: LineEnding? {
        var winner: (style: LineEnding, count: Int) = (.lf, lfCount)
        for candidate in [(LineEnding.crlf, crlfCount), (.cr, crCount)] where candidate.1 > winner.count {
            winner = (candidate.0, candidate.1)
        }
        switch winner.count {
        case 0:
            return nil
        default:
            return winner.style
        }
    }
}

public extension TextBuffer {
    /// Scans the buffer chunk-wise (O(n) bytes, no materialization) and
    /// counts each break style. CRLF pairs spanning chunk boundaries count
    /// correctly. Byte-level scanning is safe: UTF-8 continuation bytes are
    /// ≥ 0x80, so every 0x0A/0x0D byte is a genuine line break.
    ///
    /// - Returns: Statistics about the line-ending styles in the buffer.
    func lineEndingStats() -> LineEndingStats {
        var lf = 0
        var crlf = 0
        var cr = 0
        var pendingCR = false
        for chunk in chunks() {
            for byte in chunk.bytes {
                switch byte {
                case 0x0D:
                    if pendingCR {
                        cr += 1
                    }
                    pendingCR = true
                case 0x0A:
                    if pendingCR {
                        crlf += 1
                        pendingCR = false
                    } else {
                        lf += 1
                    }
                default:
                    if pendingCR {
                        cr += 1
                        pendingCR = false
                    }
                }
            }
        }
        if pendingCR {
            cr += 1
        }
        return LineEndingStats(lfCount: lf, crlfCount: crlf, crCount: cr)
    }

    /// Line-ending statistics over at most the first `byteLimit` bytes.
    ///
    /// Huge files use this instead of ``lineEndingStats()``: the dominant
    /// style is what save fidelity and the status bar need, and a sample
    /// from the head of the file answers that as well as a full scan would
    /// while costing a bounded amount of work. A file whose line-ending
    /// style changes after the first megabyte is malformed by any editor's
    /// reckoning; we pick the dominant style of the part we looked at and
    /// preserve unedited bytes verbatim on save regardless.
    ///
    /// - Parameter byteLimit: The maximum number of leading bytes to scan;
    ///   clamped to the buffer's length.
    /// - Returns: Statistics about the line-ending styles in that prefix.
    func lineEndingStats(limitedToFirst byteLimit: Int) -> LineEndingStats {
        let end = ByteOffset(min(byteLimit, utf8Count))
        var lf = 0
        var crlf = 0
        var cr = 0
        var pendingCR = false
        for chunk in chunks(in: ByteOffset(0) ..< end) {
            for byte in chunk.bytes {
                switch byte {
                case 0x0D:
                    if pendingCR {
                        cr += 1
                    }
                    pendingCR = true
                case 0x0A:
                    if pendingCR {
                        crlf += 1
                        pendingCR = false
                    } else {
                        lf += 1
                    }
                default:
                    if pendingCR {
                        cr += 1
                        pendingCR = false
                    }
                }
            }
        }
        if pendingCR {
            cr += 1
        }
        return LineEndingStats(lfCount: lf, crlfCount: crlf, crCount: cr)
    }

    /// A new buffer (version 0) with every line break rewritten to `target`.
    ///
    /// - Parameter target: The line-ending style to convert all breaks to.
    /// - Returns: A new buffer with all line endings converted, at version 0.
    func convertingLineEndings(to target: LineEnding) -> TextBuffer {
        let targetBytes = Array(target.rawValue.utf8)
        var out = [UInt8]()
        out.reserveCapacity(utf8Count)
        var pendingCR = false
        for chunk in chunks() {
            for byte in chunk.bytes {
                if pendingCR {
                    out.append(contentsOf: targetBytes)
                    pendingCR = false
                    if byte == 0x0A {
                        continue
                    } // the LF half of a CRLF pair
                }
                switch byte {
                case 0x0D: pendingCR = true
                case 0x0A: out.append(contentsOf: targetBytes)
                default: out.append(byte)
                }
            }
        }
        if pendingCR {
            out.append(contentsOf: targetBytes)
        }
        // Output bytes are built from UTF-8 buffer content plus ASCII line-break bytes, so decoding always succeeds.
        return TextBuffer(String(bytes: out, encoding: .utf8) ?? "")
    }
}
