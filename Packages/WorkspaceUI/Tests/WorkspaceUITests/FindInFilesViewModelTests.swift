import DocumentCore
import Foundation
import SearchKit
import Testing
@testable import WorkspaceUI

@Suite("FindInFilesViewModelTests")
@MainActor
struct FindInFilesViewModelTests {
    private func waitForSearch(vm: FindInFilesViewModel) async throws {
        for _ in 0 ..< 30 {
            if !vm.isSearching, !vm.results.isEmpty {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func waitForReplace(vm: FindInFilesViewModel) async throws {
        for _ in 0 ..< 30 {
            if !vm.isReplacing, vm.lastReplaceCount != nil {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

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

        try await waitForSearch(vm: vm)
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

    @Test func performReplaceAllExecutesBatchReplacement() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("test.txt")
        try "oldValue in text\nanother oldValue".write(to: file, atomically: true, encoding: .utf8)

        let vm = FindInFilesViewModel(searchFolder: tempDir)
        vm.query = "oldValue"
        vm.replacement = "newValue"
        vm.performSearch()

        try await waitForSearch(vm: vm)
        #expect(vm.results.count == 1)
        #expect(vm.totalMatchesCount == 2)

        vm.performReplaceAll()
        try await waitForReplace(vm: vm)

        #expect(vm.lastReplaceCount == 2)
        let updatedContent = try String(contentsOf: file, encoding: .utf8)
        #expect(updatedContent == "newValue in text\nanother newValue")
    }
}
