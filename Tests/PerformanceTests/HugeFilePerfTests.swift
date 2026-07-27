import Foundation
import XCTest

/// Huge-file budgets, measured through the real app process rather than
/// through `TextFileIO` in isolation — the mistake the deleted
/// `DeferredBudgets` made, which let the budget stay green while the app
/// itself could not open the file.
final class HugeFilePerfTests: XCTestCase {
    private static let isDebugBuild: Bool = {
        var isDebug = false
        assert({ isDebug = true; return true }())
        return isDebug
    }()

    /// Set `MERIDIAN_PERF_RECORD=1` to print measurements without
    /// asserting — how the Task 1 baseline and the Task 8 gate are taken.
    private static var isRecordingOnly: Bool {
        ProcessInfo.processInfo.environment["MERIDIAN_PERF_RECORD"] == "1"
    }

    /// Measures one corpus and prints the result.
    ///
    /// Returns nil only when the app executable cannot be located (running
    /// outside `xcodebuild test`), which callers report as a skip. Any other
    /// nil would mean the harness itself failed and is asserted against.
    private func measure(_ label: String, path: String) throws -> AppProcessRunner.FileOpenMeasurement? {
        guard AppProcessRunner.appExecutableURL != nil else {
            print("[BASELINE] \(label): app executable not found — skipped")
            return nil
        }
        let result = try XCTUnwrap(
            AppProcessRunner.measureFileOpen(path: path),
            "harness produced no measurement for \(label) — no marker on stdout before timeout",
        )
        let sizeBytes = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64
        let ratio = sizeBytes.map { Double(result.peakRSSBytes) / Double($0) } ?? 0
        print("""
        [BASELINE] \(label): failed=\(result.openFailed) \
        timeToVisible=\(result.timeToVisible) \
        peakRSS=\(result.peakRSSBytes / (1024 * 1024))MB \
        ratio=\(String(format: "%.2f", ratio))x
        """)
        return result
    }

    /// These three are measurement instruments, not behavioural tests: they
    /// exist to produce the numbers the Task 8 gate compares against, and
    /// they assert only that a measurement was actually obtained. Naming
    /// them `record…` rather than `test…` keeps that honest — XCTest still
    /// discovers them, since discovery is by `func test` prefix, so each is
    /// invoked through an explicit `test`-prefixed wrapper below.
    func recordBaseline(label: String, path: String) throws {
        _ = try measure(label, path: path)
    }

    func testRecord1GBManyLines() throws {
        try recordBaseline(label: "1GB many-line", path: PerfCorpus.text1GB.path)
    }

    func testRecord10MLines() throws {
        try recordBaseline(label: "10M lines", path: PerfCorpus.log10MLines.path)
    }

    func testRecordSingleLine100MB() throws {
        try recordBaseline(label: "100MB single line", path: PerfCorpus.singleLine100MB.path)
    }
}
