import AppKit
import SwiftUI
import WebKit

/// A live Markdown HTML preview view backed by `WKWebView`.
public struct MarkdownPreviewView: NSViewRepresentable {
    public let markdownText: String
    public let isDarkMode: Bool

    public init(markdownText: String, isDarkMode: Bool = true) {
        self.markdownText = markdownText
        self.isDarkMode = isDarkMode
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        updateHTMLContent(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        updateHTMLContent(in: nsView)
    }

    private func updateHTMLContent(in webView: WKWebView) {
        let htmlContent = generateHTML(from: markdownText, isDarkMode: isDarkMode)
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    private func generateHTML(from markdown: String, isDarkMode: Bool) -> String {
        let escapedMarkdown = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let bgColor = isDarkMode ? "#1e1e1e" : "#ffffff"
        let textColor = isDarkMode ? "#d4d4d4" : "#24292e"
        let codeBgColor = isDarkMode ? "#2d2d2d" : "#f6f8fa"
        let style = cssStyle(bgColor: bgColor, textColor: textColor, codeBgColor: codeBgColor)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(style)</style>
        </head>
        <body>
        <pre>\(escapedMarkdown)</pre>
        </body>
        </html>
        """
    }

    private func cssStyle(bgColor: String, textColor: String, codeBgColor: String) -> String {
        """
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            background-color: \(bgColor);
            color: \(textColor);
            padding: 20px;
            margin: 0;
          }
          h1, h2, h3, h4, h5, h6 {
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
          }
          h1 { font-size: 2em; border-bottom: 1px solid \(codeBgColor); padding-bottom: .3em; }
          h2 { font-size: 1.5em; border-bottom: 1px solid \(codeBgColor); padding-bottom: .3em; }
          code, pre {
            font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
            background-color: \(codeBgColor);
            border-radius: 6px;
          }
          code { padding: .2em .4em; font-size: 85%; }
          pre { padding: 16px; overflow: auto; line-height: 1.45; }
          pre code { padding: 0; background: transparent; }
          blockquote {
            padding: 0 1em;
            color: #8b949e;
            border-left: .25em solid #30363d;
            margin: 0 0 16px 0;
          }
          a { color: #58a6ff; text-decoration: none; }
          a:hover { text-decoration: underline; }
          hr { height: 0.25em; padding: 0; margin: 24px 0; background-color: #30363d; border: 0; }
        """
    }
}
