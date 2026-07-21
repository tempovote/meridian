import Foundation
import XCTest

final class LaunchAndMemoryPerfTests: XCTestCase {
    private static let isDebugBuild: Bool = {
        var isDebug = false
        assert({ isDebug = true; return true }())
        return isDebug
    }()

    private static let scale: Int = max(
        ProcessInfo.processInfo.environment["MERIDIAN_PERF_SCALE"].flatMap(Int.init) ?? 1,
        1,
    )

    func testColdLaunchBudget() throws {
        let scale = Self.scale
        guard let duration = try AppProcessRunner.measureColdLaunch() else {
            // If the application binary is not located (e.g. running in isolated SPM unit tests), skip gracefully
            return
        }

        if !Self.isDebugBuild {
            let budget = Duration.milliseconds(700 * scale)
            XCTAssertLessThan(
                duration, budget,
                "Cold launch budget regressed: \(duration) (budget: \(budget))",
            )
        }
    }

    func testIdleMemoryBudget() throws {
        let scale = Self.scale
        guard let rssMB = try AppProcessRunner.measureIdleMemoryMB(tabCount: 10) else {
            // If the application binary is not located, skip gracefully
            return
        }

        if !Self.isDebugBuild {
            let maxBudgetMB = Double(150 * scale)
            XCTAssertLessThan(
                rssMB, maxBudgetMB,
                "Idle memory budget regressed: \(rssMB) MB (budget: \(maxBudgetMB) MB)",
            )
        }
    }
}
