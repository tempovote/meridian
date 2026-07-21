import AppKit

/// Parses a `"#RRGGBB"` hex color string (as used in `.meridiantheme` JSON)
/// into an `NSColor`. Only 6-digit RGB (no alpha, no 3-digit shorthand) is
/// supported — every bundled theme uses this format exclusively.
enum HexColor {
    static func nsColor(fromHex hex: String) -> NSColor? {
        var chars = hex
        if chars.hasPrefix("#") {
            chars.removeFirst()
        }
        guard chars.count == 6, let value = UInt32(chars, radix: 16) else {
            return nil
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
