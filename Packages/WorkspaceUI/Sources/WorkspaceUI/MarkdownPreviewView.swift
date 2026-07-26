import AppKit
import SwiftUI

/// Block-level Markdown data model for rich native SwiftUI rendering.
public enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case listItem(text: String)
    case codeBlock(language: String, code: String)
    case blockquote(text: String)
    case space(id: String)

    public var id: String {
        switch self {
        case let .heading(level, text): "h-\(level)-\(text)"
        case let .paragraph(text): "p-\(text.prefix(20))-\(text.hashValue)"
        case let .listItem(text): "li-\(text.prefix(20))-\(text.hashValue)"
        case let .codeBlock(lang, code): "code-\(lang)-\(code.hashValue)"
        case let .blockquote(text): "bq-\(text.prefix(20))-\(text.hashValue)"
        case let .space(spaceID): spaceID
        }
    }
}

/// A native, high-performance Markdown preview view using SwiftUI layout blocks.
public struct MarkdownPreviewView: View {
    public let markdownText: String
    public let isDarkMode: Bool

    public init(markdownText: String, isDarkMode: Bool = true) {
        self.markdownText = markdownText
        self.isDarkMode = isDarkMode
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parseBlocks(markdownText)) { block in
                    renderBlock(block)
                }
            }
            .padding(20)
        }
        .background(isDarkMode ? Color(white: 0.12) : Color.white)
        .foregroundColor(isDarkMode ? Color(white: 0.90) : Color.black)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .bold()
                .padding(.top, level == 1 ? 12 : 6)
                .padding(.bottom, 2)

        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.system(size: 14))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case let .listItem(text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
                Text(inlineMarkdown(text))
                    .font(.system(size: 14))
            }
            .padding(.leading, 6)

        case let .codeBlock(_, code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isDarkMode ? Color(white: 0.18) : Color(white: 0.94))
                .cornerRadius(6)

        case let .blockquote(text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4)
                Text(inlineMarkdown(text))
                    .font(.system(size: 14))
                    .italic()
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)

        case .space:
            Spacer().frame(height: 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 22, weight: .bold)
        case 2: .system(size: 17, weight: .bold)
        case 3: .system(size: 15, weight: .semibold)
        default: .system(size: 14, weight: .semibold)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func parseBlocks(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var inCode = false
        var codeLang = ""
        var codeLines: [String] = []

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    inCode = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCode {
                codeLines.append(line)
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                blocks.append(parseSingleLine(trimmed: trimmed, rawLine: line, index: index))
            }
        }

        if inCode {
            blocks.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
        }

        return blocks
    }

    private func parseSingleLine(trimmed: String, rawLine: String, index: Int) -> MarkdownBlock {
        if trimmed.isEmpty {
            return .space(id: "space-\(index)")
        }
        if trimmed.hasPrefix("# ") {
            return .heading(level: 1, text: String(trimmed.dropFirst(2)))
        }
        if trimmed.hasPrefix("## ") {
            return .heading(level: 2, text: String(trimmed.dropFirst(3)))
        }
        if trimmed.hasPrefix("### ") {
            return .heading(level: 3, text: String(trimmed.dropFirst(4)))
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return .listItem(text: String(trimmed.dropFirst(2)))
        }
        if trimmed.hasPrefix("> ") {
            return .blockquote(text: String(trimmed.dropFirst(2)))
        }
        return .paragraph(text: rawLine)
    }
}
