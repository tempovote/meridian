@testable import DocumentCore

/// SplitMix64 — deterministic RNG so property-test failures are reproducible.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// Snippets deliberately mixing ASCII, CRLF, multibyte, and ZWJ sequences.
let fuzzCorpus: [String] = [
    "hello", "\n", "\r\n", "a", "",
    "tiếng Việt", "日本語テキスト", "é́́", // stacked combining marks
    "😀", "👨\u{200D}👩\u{200D}👧", "🇻🇳",
    String(repeating: "x", count: 3000), // forces multi-leaf inserts
    "line1\nline2\nline3\n",
]

/// Picks a random scalar boundary in `bytes` using `rng`.
func randomScalarBoundary(in bytes: [UInt8], using rng: inout SeededRandom) -> Int {
    guard !bytes.isEmpty else { return 0 }
    return scalarBoundary(in: bytes, notAfter: Int.random(in: 0 ... bytes.count, using: &rng))
}
