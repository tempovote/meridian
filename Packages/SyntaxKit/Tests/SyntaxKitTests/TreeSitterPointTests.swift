import DocumentCore
import Testing
@testable import SyntaxKit

@Suite("TreeSitterPointTests")
struct TreeSitterPointTests {
    @Test func firstLineFirstColumn() {
        let buffer = TextBuffer("hello\nworld")
        let point = treeSitterPoint(for: ByteOffset(0), in: buffer)
        #expect(point.row == 0)
        #expect(point.column == 0)
    }

    @Test func midFirstLine() {
        let buffer = TextBuffer("hello\nworld")
        // byte 3 is inside "hello" (h=0,e=1,l=2,l=3)
        let point = treeSitterPoint(for: ByteOffset(3), in: buffer)
        #expect(point.row == 0)
        #expect(point.column == 3)
    }

    @Test func secondLineByteColumn() {
        let buffer = TextBuffer("hello\nworld")
        // byte 8 is 'r' in "world" (line 2 starts at byte 6: w=6,o=7,r=8)
        let point = treeSitterPoint(for: ByteOffset(8), in: buffer)
        #expect(point.row == 1)
        #expect(point.column == 2)
    }

    @Test func multiByteUTF8CharactersCountAsBytesNotScalars() {
        // "café\n" — é is 2 UTF-8 bytes (c=0,a=1,f=2,é=3..4,\n=5)
        let buffer = TextBuffer("café\nx")
        let point = treeSitterPoint(for: ByteOffset(6), in: buffer)
        #expect(point.row == 1)
        #expect(point.column == 0)
    }
}
