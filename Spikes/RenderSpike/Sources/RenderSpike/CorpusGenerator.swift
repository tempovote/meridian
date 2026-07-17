import Foundation

/// Which corpus shape to generate (spec: 1 GB mixed text, 10M-line log,
/// 100 MB single line).
enum CorpusKind: String {
    case mixedText = "mixed"
    case logLines = "log"
    case singleLine = "single"
}

/// SplitMix64 — deterministic, seedable; same idiom as DocumentCore's test
/// support (not importable from here, so re-declared: spike code may not
/// create dependencies on test internals).
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Streams a deterministic corpus to disk in ~8 MB flushes.
enum CorpusGenerator {
    static let asciiWords = [
        "func", "let", "var", "return", "struct", "extension", "buffer",
        "offset", "viewport", "layout", "fragment", "paragraph", "rope",
    ]
    static let vietnameseSentences = [
        "Trình soạn thảo văn bản gốc cho macOS.",
        "Hiệu năng là ưu tiên hàng đầu của dự án.",
        "Tệp một gigabyte phải cuộn mượt mà.",
    ]
    static let emojiBits = ["😀", "👨‍👩‍👧‍👦", "🇻🇳", "🎉", "café", "naïve"]

    static func generate(kind: CorpusKind, sizeBytes: Int, seed: UInt64, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var rng = SplitMix64(seed: seed)
        var pending = Data()
        pending.reserveCapacity(9_000_000)
        var written = 0
        while written < sizeBytes {
            let chunk = nextChunk(kind: kind, rng: &rng)
            pending.append(contentsOf: chunk.utf8)
            written += chunk.utf8.count
            if pending.count >= 8_000_000 {
                try handle.write(contentsOf: pending)
                pending.removeAll(keepingCapacity: true)
            }
        }
        if !pending.isEmpty { try handle.write(contentsOf: pending) }
    }

    private static func nextChunk(kind: CorpusKind, rng: inout SplitMix64) -> String {
        switch kind {
        case .logLines:
            let ts = 1_700_000_000 + Int(rng.next() % 100_000_000)
            return "[\(ts)] INFO worker-\(rng.next() % 64): request \(rng.next() % 1_000_000) done\n"
        case .singleLine:
            return String(repeating: "ab cd ef gh ", count: 64) // 768 bytes, no \n
        case .mixedText:
            let roll = rng.next() % 10
            if roll < 6 { // code-like ASCII line, length 0-200
                let words = Int(rng.next() % 25)
                var line = ""
                for _ in 0 ..< words {
                    line += asciiWords[Int(rng.next() % UInt64(asciiWords.count))] + " "
                }
                return line + "\n"
            } else if roll < 8 { // Vietnamese
                return vietnameseSentences[Int(rng.next() % UInt64(vietnameseSentences.count))] + "\n"
            } else if roll < 9 { // emoji-bearing
                return "note \(emojiBits[Int(rng.next() % UInt64(emojiBits.count))]) end\n"
            } else { // empty/short
                return rng.next() % 2 == 0 ? "\n" : "x\n"
            }
        }
    }
}
