import DocumentCore
import FileKit
import Foundation
import XCTest
@testable import Meridian

/// Documents performance budget items asserting memory-mapped huge file loading.
final class DeferredBudgets: XCTestCase {
    private static let isDebugBuild: Bool = {
        var isDebug = false
        assert({ isDebug = true; return true }())
        return isDebug
    }()

    private static let scale: Int = max(
        ProcessInfo.processInfo.environment["MERIDIAN_PERF_SCALE"].flatMap(Int.init) ?? 1,
        1,
    )

    /// Open 1 GB file (huge-file mode) < 1.5 s budget asserted in M7.
    func testOpen1GBFileHugeFileModeBudget() throws {
        let fileURL = PerfCorpus.text1GB
        let scale = Self.scale

        let clock = ContinuousClock()
        let start = clock.now

        let textFile = try TextFileIO.loadTextFile(at: fileURL)
        XCTAssertGreaterThanOrEqual(textFile.byteSize, 1_000_000_000)

        let duration = start.duration(to: clock.now)

        if !Self.isDebugBuild {
            let budget = Duration.milliseconds(1500 * scale)
            XCTAssertLessThan(
                duration, budget,
                "Open 1GB file budget regressed: \(duration) (budget: \(budget))",
            )
        }
    }
}
