import Foundation
import Testing
@testable import WorkspaceUI

@Suite("FileTreeViewModelTests")
@MainActor
struct FileTreeViewModelTests {
    @Test func loadsDirectoryStructure() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("SubFolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("a_file.txt")
        let file2 = subDir.appendingPathComponent("b_file.swift")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)
        try "print(1)".write(to: file2, atomically: true, encoding: .utf8)

        let vm = FileTreeViewModel(rootURL: tempDir)

        #expect(vm.rootItems.count == 2)
        // Folders sort first
        #expect(vm.rootItems[0].name == "SubFolder")
        #expect(vm.rootItems[0].isDirectory == true)
        #expect(vm.rootItems[0].children?.count == 1)
        #expect(vm.rootItems[0].children?[0].name == "b_file.swift")

        #expect(vm.rootItems[1].name == "a_file.txt")
        #expect(vm.rootItems[1].isDirectory == false)
    }

    @Test func selectFileTriggersCallback() throws {
        let tempDir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("test.swift").resolvingSymlinksInPath()
        try "code".write(to: file, atomically: true, encoding: .utf8)

        let vm = FileTreeViewModel(rootURL: tempDir)

        var selectedURL: URL?
        vm.onSelectFile = { url in
            selectedURL = url.resolvingSymlinksInPath()
        }

        if let item = vm.rootItems.first {
            vm.selectItem(item)
            #expect(vm.selectedURL?.resolvingSymlinksInPath() == file)
            #expect(selectedURL == file)
        } else {
            Issue.record("Expected item in rootItems")
        }
    }
}
