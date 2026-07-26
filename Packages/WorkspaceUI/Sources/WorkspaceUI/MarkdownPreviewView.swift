import AppKit
import SwiftUI

/// A native, high-performance Markdown preview view using SwiftUI and `AttributedString`.
public struct MarkdownPreviewView: View {
    public let markdownText: String
    public let isDarkMode: Bool

    public init(markdownText: String, isDarkMode: Bool = true) {
        self.markdownText = markdownText
        self.isDarkMode = isDarkMode
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let attributedString = parseMarkdown(markdownText) {
                    Text(attributedString)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(markdownText)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(isDarkMode ? Color(white: 0.12) : Color.white)
        .foregroundColor(isDarkMode ? Color(white: 0.90) : Color.black)
    }

    private func parseMarkdown(_ text: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        return try? AttributedString(markdown: text, options: options)
    }
}
