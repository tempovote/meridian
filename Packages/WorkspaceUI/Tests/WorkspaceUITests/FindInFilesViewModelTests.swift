import DocumentCore
import Foundation
import SearchKit
import Testing
@testable import WorkspaceUI

@Suite("FindInFilesViewModelTests")
@MainActor
struct FindInFilesViewModelTests {
    @Test func statusTextReflectsSearchState() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("test.txt")
        try "find this word\nand this word again".write(to: file, atomically: true, encoding: .utf8)

        let vm = FindInFilesViewModel(searchFolder: tempDir)
        #expect(vm.statusText == "Type a search query")

        vm.query = "word"
        vm.performSearch()

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.results.count == 1)
        #expect(vm.totalMatchesCount == 2)
        #expect(vm.statusText == "2 matches in 1 file")
    }

    @Test func selectMatchTriggersCallback() {
        let vm = FindInFilesViewModel()
        var selectedURL: URL?
        var selectedMatch: FileMatch?

        vm.onSelectMatch = { url, match in
            selectedURL = url
            selectedMatch = match
        }

        let dummyURL = URL(fileURLWithPath: "/tmp/dummy.txt")
        let dummyMatch = FileMatch(line: 5, column: 2, range: ByteOffset(10) ..< ByteOffset(15), lineSnippet: "dummy")

        vm.selectMatch(dummyMatch, in: dummyURL)
        #expect(selectedURL == dummyURL)
        #expect(selectedMatch == dummyMatch)
        #expect(vm.selectedMatchID == dummyMatch.id)
    }
}
