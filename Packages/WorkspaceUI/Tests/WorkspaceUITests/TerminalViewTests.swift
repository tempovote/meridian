import Foundation
import Testing
@testable import WorkspaceUI

@Suite("TerminalViewTests")
struct TerminalViewTests {
    /// A terminal opened for the first time on a document must start in that
    /// document's own folder — not wherever the app process happened to be
    /// launched from (LaunchServices leaves that at "/" for a GUI launch, so
    /// `git status` and every relative path silently landed in the wrong
    /// place).
    @Test func fallsBackToTheDocumentsContainingFolder() {
        let documentURL = URL(fileURLWithPath: "/Users/example/project/File.swift")
        let resolved = TerminalView.fallbackWorkingDirectory(documentURL: documentURL)
        #expect(resolved == "/Users/example/project")
    }

    /// An untitled document has no folder to fall back to; home is the
    /// least surprising starting point, not the app's own process cwd.
    @Test func fallsBackToHomeDirectoryWhenThereIsNoDocument() {
        let resolved = TerminalView.fallbackWorkingDirectory(documentURL: nil)
        #expect(resolved == FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
