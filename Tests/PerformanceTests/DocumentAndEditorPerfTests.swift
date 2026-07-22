import DocumentCore
import EditorUI
import FileKit
import Foundation
import SearchKit
import XCTest
@testable import Meridian

final class DocumentAndEditorPerfTests: XCTestCase {
    private static let isDebugBuild: Bool = {
        var isDebug = false
        assert({ isDebug = true; return true }())
        return isDebug
    }()

    private static let scale: Int = max(
        ProcessInfo.processInfo.environment["MERIDIAN_PERF_SCALE"].flatMap(Int.init) ?? 1,
        1,
    )

    @MainActor
    func testOpen100MBFileBudget() throws {
        let fileURL = PerfCorpus.text100MB
        let scale = Self.scale

        let clock = ContinuousClock()
        let start = clock.now

        let textFile = try TextFileIO.loadTextFile(at: fileURL)
        let engine = TextKit2Engine(
            themeEngine: AppDelegate.themeEngine,
            settingsStore: AppDelegate.settingsStore,
        )
        _ = EditorViewModel(documentModel: DocumentModel(buffer: textFile.buffer), engine: engine)

        let duration = start.duration(to: clock.now)

        if !Self.isDebugBuild {
            let budget = Duration.milliseconds(500 * scale)
            XCTAssertLessThan(
                duration, budget,
                "Open 100MB file budget regressed: \(duration) (budget: \(budget))",
            )
        }
    }

    @MainActor
    func testFindAllIn100MBBudget() throws {
        let fileURL = PerfCorpus.text100MBSearch
        let scale = Self.scale

        let textFile = try TextFileIO.loadTextFile(at: fileURL)
        let buffer = textFile.buffer

        let clock = ContinuousClock()
        let start = clock.now

        let searchEngine = SearchEngine()
        let results = searchEngine.findAll(
            query: "SEARCH_KEYWORD_TARGET_MATCH_100MB",
            in: buffer,
            options: [.caseSensitive],
        )

        let duration = start.duration(to: clock.now)
        XCTAssertGreaterThan(results.count, 0)

        if !Self.isDebugBuild {
            let budget = Duration.seconds(1 * scale)
            XCTAssertLessThan(
                duration, budget,
                "Find-all in 100MB budget regressed: \(duration) (budget: \(budget))",
            )
        }
    }

    @MainActor
    func testKeystrokeLatency100MBBudget() throws {
        let fileURL = PerfCorpus.text100MB
        let scale = Self.scale

        let textFile = try TextFileIO.loadTextFile(at: fileURL)
        let engine = TextKit2Engine(
            themeEngine: AppDelegate.themeEngine,
            settingsStore: AppDelegate.settingsStore,
        )
        let viewModel = EditorViewModel(documentModel: DocumentModel(buffer: textFile.buffer), engine: engine)

        let sampleCount = Self.isDebugBuild ? 5 : 50
        var durations: [Duration] = []
        durations.reserveCapacity(sampleCount)

        let clock = ContinuousClock()
        for i in 0 ..< sampleCount {
            let offset = ByteOffset(i * 100)
            let edit = EditTransaction(
                baseVersion: viewModel.buffer.version,
                edits: [Edit(range: offset ..< offset, replacement: "a")],
                selectionBefore: viewModel.selection,
                selectionAfter: SelectionSet(caretAt: ByteOffset(offset.value + 1)),
            )
            let editStart = clock.now
            viewModel.perform(edit)
            durations.append(editStart.duration(to: clock.now))
        }

        durations.sort()
        let p99Index = Int(Double(sampleCount) * 0.99)
        let p99Duration = durations[min(p99Index, sampleCount - 1)]

        if !Self.isDebugBuild {
            let budget = Duration.milliseconds(16 * scale)
            XCTAssertLessThan(
                p99Duration, budget,
                "Keystroke p99 latency regressed: \(p99Duration) (budget: \(budget))",
            )
        }
    }
}
