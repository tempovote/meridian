import Foundation
import Testing
@testable import DocumentCore

/// Env-configured fuzz parameters shared by all fuzz tests.
enum FuzzConfig {
    static var operations: Int {
        ProcessInfo.processInfo.environment["MERIDIAN_FUZZ_OPS"].flatMap(Int.init) ?? 20000
    }

    static var seed: UInt64 {
        ProcessInfo.processInfo.environment["MERIDIAN_FUZZ_SEED"].flatMap(UInt64.init) ?? 0x4D31_5035
    }
}

/// Walks the rope and verifies the documented B-tree invariants: uniform
/// leaf depth; inner fanout within 1...maxFanout, and >= minFanout for
/// inner nodes below the root (the root is exempt from `minFanout` — see
/// `Node.build`'s doc comment and `RopeOpsTests.assertMinFanout`, which
/// documents the same root exemption). Returns a violation description, or
/// nil.
func validateTree(_ root: Node) -> String? {
    // `Result`'s `Failure` must be `Error`; `String` isn't, so violations
    // are wrapped in this trivial carrier.
    struct Violation: Error { let message: String }

    func walk(_ node: Node, depth: Int, isRoot: Bool) -> Result<Int, Violation> {
        switch node {
        case .leaf:
            return .success(depth)
        case let .inner(children, _, _):
            if children.isEmpty || children.count > Node.maxFanout {
                return .failure(Violation(
                    message: "inner fanout \(children.count) outside 1...\(Node.maxFanout) at depth \(depth)",
                ))
            }
            if !isRoot, children.count < Node.minFanout {
                return .failure(Violation(
                    message: "non-root inner fanout \(children.count) below \(Node.minFanout) at depth \(depth)",
                ))
            }
            return walkChildren(children, depth: depth)
        }
    }

    func walkChildren(_ children: [Node], depth: Int) -> Result<Int, Violation> {
        var leafDepth: Int?
        for child in children {
            switch walk(child, depth: depth + 1, isRoot: false) {
            case let .failure(violation):
                return .failure(violation)
            case let .success(childLeafDepth):
                if let expected = leafDepth, expected != childLeafDepth {
                    return .failure(Violation(message: "leaf depth mismatch \(expected) vs \(childLeafDepth)"))
                }
                leafDepth = childLeafDepth
            }
        }
        return .success(leafDepth ?? depth)
    }

    switch walk(root, depth: 0, isRoot: true) {
    case let .failure(violation): return violation.message
    case .success: return nil
    }
}

/// Drives random scalar-boundary edits against a `TextBuffer` and a
/// `[UInt8]` reference, checking invariants at checkpoints. Failures are
/// recorded (via `#expect`/`Issue.record`) tagged with seed + op index so
/// they're reproducible.
struct BufferFuzzEngine {
    /// A retained (buffer, reference) pair from an earlier op, used to check
    /// that later mutations never retroactively alter it (COW isolation). A
    /// named type rather than a tuple — SwiftLint caps tuples at 2 members.
    private struct Snapshot {
        let buffer: TextBuffer
        let reference: [UInt8]
        let opIndex: Int
    }

    private var rng: SeededRandom
    private let seed: UInt64
    private var buffer = TextBuffer()
    private var reference: [UInt8] = []
    private var snapshots: [Snapshot] = []

    private static let sizeCap = 256 * 1024
    private static let checkpointInterval = 1000
    private static let snapshotInterval = 500
    private static let maxSnapshots = 8

    init(seed: UInt64) {
        self.seed = seed
        rng = SeededRandom(seed: seed)
    }

    mutating func run(operations: Int) {
        for opIndex in 0 ..< operations {
            step(opIndex: opIndex)
            if opIndex % Self.snapshotInterval == 0 {
                snapshots.append(Snapshot(buffer: buffer, reference: reference, opIndex: opIndex))
                if snapshots.count > Self.maxSnapshots {
                    snapshots.removeFirst()
                }
            }
            if opIndex % Self.checkpointInterval == 0 {
                checkInvariants(opIndex: opIndex)
            }
        }
        checkInvariants(opIndex: operations)
    }

    private mutating func step(opIndex _: Int) {
        let deleteBias = reference.count > Self.sizeCap ? 7 : 3
        let roll = Int.random(in: 0 ..< 10, using: &rng)
        if roll < deleteBias, !reference.isEmpty {
            deleteRandomRange()
        } else {
            insertOrReplaceRandomRange()
        }
    }

    /// Deletes a random scalar-boundary range.
    private mutating func deleteRandomRange() {
        let bound1 = randomScalarBoundary(in: reference, using: &rng)
        let bound2 = randomScalarBoundary(in: reference, using: &rng)
        let range = min(bound1, bound2) ..< max(bound1, bound2)
        buffer.replaceSubrange(ByteOffset(range.lowerBound) ..< ByteOffset(range.upperBound), with: "")
        reference.removeSubrange(range)
    }

    /// Inserts a random corpus snippet (or replaces a small range: 1-in-4).
    private mutating func insertOrReplaceRandomRange() {
        let snippet = fuzzCorpus[Int.random(in: 0 ..< fuzzCorpus.count, using: &rng)]
        let start = randomScalarBoundary(in: reference, using: &rng)
        var end = start
        if Int.random(in: 0 ..< 4, using: &rng) == 0 {
            end = scalarBoundary(in: reference, notAfter: min(start + 64, reference.count))
        }
        buffer.replaceSubrange(ByteOffset(start) ..< ByteOffset(max(start, end)), with: snippet)
        reference.replaceSubrange(start ..< max(start, end), with: Array(snippet.utf8))
    }

    private mutating func checkInvariants(opIndex: Int) {
        let context = "seed 0x\(String(seed, radix: 16)), op \(opIndex)"
        checkContent(context: context)
        checkTree(context: context)
        checkSnapshotIsolation(context: context)
    }

    private func checkContent(context: String) {
        #expect(Array(buffer.string.utf8) == reference, "content diverged (\(context))")
        #expect(buffer.utf8Count == reference.count, "utf8Count diverged (\(context))")
        guard let decoded = String(bytes: reference, encoding: .utf8) else {
            Issue.record("reference model is not valid UTF-8 (\(context))")
            return
        }
        #expect(buffer.utf16Count == decoded.utf16.count, "utf16Count diverged (\(context))")
        let newlines = reference.lazy.filter { $0 == 0x0A }.count
        #expect(buffer.lineCount == newlines + 1, "lineCount diverged (\(context))")
    }

    private func checkTree(context: String) {
        if let violation = validateTree(buffer.root) {
            Issue.record("tree invariant violated: \(violation) (\(context))")
        }
    }

    private func checkSnapshotIsolation(context: String) {
        for snapshot in snapshots {
            #expect(
                Array(snapshot.buffer.string.utf8) == snapshot.reference,
                "snapshot isolation broken for op \(snapshot.opIndex) (\(context))",
            )
        }
    }
}
