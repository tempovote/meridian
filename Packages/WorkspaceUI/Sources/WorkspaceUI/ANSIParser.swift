import Foundation

/// A terminal foreground colour, as a code rather than a rendered colour.
///
/// Keeping SwiftUI's `Color` out of the parser's output is what makes the
/// parser testable: two `Color` values built the same way are not reliably
/// comparable, while these cases are. Mapping a code to the colour actually
/// drawn is the view's job, in `TerminalView`.
public enum ANSIColor: Equatable, Sendable {
    /// No colour selected, or explicitly reset by SGR 0. The view substitutes
    /// whatever colour the caller asked the line to be drawn in.
    case `default`
    /// SGR codes 30–37.
    case standard(Int)
    /// SGR codes 90–97.
    case bright(Int)
}

/// A run of terminal output sharing one colour.
public struct ANSISegment: Equatable, Sendable {
    public let text: String
    public let color: ANSIColor

    public init(text: String, color: ANSIColor) {
        self.text = text
        self.color = color
    }
}

/// Splits terminal output into coloured runs, discarding the escape
/// sequences themselves.
public enum ANSIParser {
    /// Parses SGR (`ESC [ … m`) sequences. Any other escape sequence, and
    /// any malformed one, is passed through as literal text rather than
    /// silently consuming the rest of the output.
    ///
    /// Empty input yields no segments. Callers that need a blank line to
    /// occupy a row must supply that themselves — the parser describes the
    /// text it was given, and an empty segment is a rendering concern.
    public static func parse(_ raw: String) -> [ANSISegment] {
        var segments: [ANSISegment] = []
        var current = ""
        var currentColor = ANSIColor.default
        var index = raw.startIndex

        func flush() {
            guard !current.isEmpty else { return }
            segments.append(ANSISegment(text: current, color: currentColor))
            current = ""
        }

        while index < raw.endIndex {
            let next = raw.index(after: index)
            let isSGRStart = raw[index] == "\u{1B}" && next < raw.endIndex && raw[next] == "["
            guard isSGRStart else {
                current.append(raw[index])
                index = next
                continue
            }
            let sequenceStart = raw.index(index, offsetBy: 2)
            guard let terminator = raw[sequenceStart...].firstIndex(of: "m") else {
                // Unterminated: treat the escape as literal text so the
                // remaining output is not swallowed.
                current.append(raw[index])
                index = next
                continue
            }
            flush()
            let codes = raw[sequenceStart ..< terminator]
                .split(separator: ";")
                .compactMap { Int($0) }
            currentColor = colour(after: codes, current: currentColor)
            index = raw.index(after: terminator)
        }
        flush()
        return segments
    }

    /// Applies a sequence's codes to the running colour. Non-colour codes
    /// (bold, underline, inverse …) are ignored rather than resetting, and
    /// the last colour code in a sequence wins.
    private static func colour(after codes: [Int], current: ANSIColor) -> ANSIColor {
        var result = current
        for code in codes {
            switch code {
            case 0: result = .default
            case 30 ... 37: result = .standard(code)
            case 90 ... 97: result = .bright(code)
            default: break
            }
        }
        return result
    }
}
