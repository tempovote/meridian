import DocumentCore
import Foundation
import Testing

/// Budgets are order-of-magnitude regression tripwires (~25× expected local
/// time), not perf targets — they catch an accidental O(n) walk sneaking
/// into a hot path, and must never flake on a noisy CI runner. Raising a
/// budget requires a justified PR, not a quiet edit. MERIDIAN_PERF_SCALE
/// multiplies both workload and budget (nightly uses 10).
@Suite(.serialized)
struct RopeBenchmarks {
    private static let isDebugBuild: Bool = {
        var isDebug = false
        assert({ isDebug = true; return true }())
        return isDebug
    }()

    static let scale = max(
        ProcessInfo.processInfo.environment["MERIDIAN_PERF_SCALE"].flatMap(Int.init) ?? 1, 1,
    )

    private func medianDuration(of work: () -> Void) -> Duration {
        let runCount = Self.isDebugBuild ? 1 : 5
        var samples: [Duration] = []
        for _ in 0 ..< runCount {
            let clock = ContinuousClock()
            samples.append(clock.measure(work))
        }
        return samples.sorted()[runCount / 2]
    }

    private func makeBuffer(lines: Int) -> TextBuffer {
        TextBuffer(String(
            repeating: "0123456789012345678901234567890123456789012345678\n",
            count: lines,
        ))
    }

    @Test func insertAtRandomPositions() {
        let scale = Self.scale
        let lineCount = Self.isDebugBuild ? 200 : 2000
        var buffer = makeBuffer(lines: lineCount * scale)
        var positions: [Int] = []
        var rng = SystemRandomNumberGenerator()
        for _ in 0 ..< (lineCount * scale) {
            positions.append(Int.random(in: 0 ... buffer.utf8Count, using: &rng))
        }
        var cursor = 0
        let median = medianDuration {
            for _ in 0 ..< (lineCount * scale) {
                let at = min(positions[cursor % positions.count], buffer.utf8Count)
                buffer.replaceSubrange(ByteOffset(at) ..< ByteOffset(at), with: "insert!!")
                cursor += 1
            }
        }
        // Debug builds only smoke-test the path; budgets are enforced by release-mode CI runs.
        if !Self.isDebugBuild {
            #expect(median < .seconds(5 * scale), "insert@random regressed: \(median)")
        }
    }

    @Test func lineLookupRoundTrips() {
        let scale = Self.scale
        let lineCount = Self.isDebugBuild ? 200 : 2000
        let probeCount = Self.isDebugBuild ? 2000 : 20000
        let buffer = makeBuffer(lines: lineCount * scale)
        let bufferLineCount = buffer.lineCount
        let median = medianDuration {
            for probe in 0 ..< (probeCount * scale) {
                let line = (probe &* 7919) % bufferLineCount
                let start = buffer.byteRange(ofLine: line).lowerBound
                let position = buffer.linePosition(of: start)
                _ = buffer.byteOffset(of: position)
            }
        }
        // Debug builds only smoke-test the path; budgets are enforced by release-mode CI runs.
        if !Self.isDebugBuild {
            #expect(median < .seconds(5 * scale), "line lookup regressed: \(median)")
        }
    }

    @Test func snapshotAndDivergeCost() {
        let scale = Self.scale
        let lineCount = Self.isDebugBuild ? 200 : 2000
        let iterationCount = Self.isDebugBuild ? 50 : 500
        var buffer = makeBuffer(lines: lineCount * scale)
        var retained: [TextBuffer] = []
        let median = medianDuration {
            for iteration in 0 ..< (iterationCount * scale) {
                let snapshot = buffer
                retained.append(snapshot)
                if retained.count > 4 {
                    retained.removeFirst()
                }
                let at = (iteration &* 4099) % (buffer.utf8Count + 1)
                buffer.replaceSubrange(ByteOffset(at) ..< ByteOffset(at), with: "d")
            }
        }
        // Debug builds only smoke-test the path; budgets are enforced by release-mode CI runs.
        if !Self.isDebugBuild {
            #expect(median < .seconds(5 * scale), "snapshot+diverge regressed: \(median)")
        }
        #expect(!retained.isEmpty)
    }
}
