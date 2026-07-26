import FileKit
import Testing

@Suite("GitServiceTests")
struct GitServiceTests {
    @Test func parseAdditionHunk() {
        let diff = """
        @@ -0,0 +1,3 @@
        +line 1
        +line 2
        +line 3
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[0] == .added)
        #expect(marks[1] == .added)
        #expect(marks[2] == .added)
    }

    @Test func parseModificationHunk() {
        let diff = """
        @@ -10,2 +10,2 @@
        -old line
        +new line
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[9] == .modified)
        #expect(marks[10] == .modified)
    }

    @Test func parseDeletionHunk() {
        let diff = """
        @@ -15,2 +15,0 @@
        -deleted line 1
        -deleted line 2
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[14] == .deleted)
    }

    @Test func parseMixedHunks() {
        let diff = """
        @@ -5,1 +5,1 @@
        -old
        +new
        @@ -20,0 +21,2 @@
        +added 1
        +added 2
        """
        let marks = GitService.parseHunks(diffOutput: diff)
        #expect(marks[4] == .modified)
        #expect(marks[20] == .added)
        #expect(marks[21] == .added)
    }
}
