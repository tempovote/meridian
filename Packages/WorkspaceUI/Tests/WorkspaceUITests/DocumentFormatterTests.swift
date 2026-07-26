import Testing
@testable import WorkspaceUI

@Suite("DocumentFormatterTests")
struct DocumentFormatterTests {
    @Test func formatJSONPrettyPrintsCorrectly() {
        let input = "{\"name\":\"Meridian\",\"version\":1,\"tags\":[\"editor\",\"text\"]}"
        let formatted = DocumentFormatter.format(text: input, languageID: "json", pretty: true, indentSize: 2)
        #expect(formatted != nil)
        #expect(formatted?.contains("\"name\"") == true)
        #expect(formatted?.contains("\"Meridian\"") == true)
        #expect(formatted?.contains("\n") == true)
    }

    @Test func formatJSONMinifiesCorrectly() {
        let input = """
        {
          "name": "Meridian",
          "version": 1
        }
        """
        let minified = DocumentFormatter.format(text: input, languageID: "json", pretty: false)
        #expect(minified != nil)
        #expect(minified?.contains("\n") == false)
        #expect(minified?.contains("\"name\":\"Meridian\"") == true)
    }

    @Test func formatXMLPrettyPrintsCorrectly() {
        let input = "<root><item id=\"1\">Value</item></root>"
        let formatted = DocumentFormatter.format(text: input, languageID: "xml", pretty: true, indentSize: 2)
        #expect(formatted != nil)
        #expect(formatted?.contains("<root>") == true)
        #expect(formatted?.contains("  <item") == true)
    }

    @Test func formatUnsupportedLanguageReturnsNil() {
        let input = "fn main() {}"
        let result = DocumentFormatter.format(text: input, languageID: "rust", pretty: true)
        #expect(result == nil)
    }
}
