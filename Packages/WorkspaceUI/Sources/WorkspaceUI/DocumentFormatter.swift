import DocumentCore
import Foundation

/// Error types returned by `DocumentFormatter`.
public enum FormatError: Error, LocalizedError {
    case unsupportedLanguage(String)
    case syntaxError(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedLanguage(lang):
            "Format is not supported for language '\(lang)'. Supported formats are JSON and XML."
        case let .syntaxError(reason):
            "Syntax error: \(reason)"
        }
    }
}

/// Provides code formatting and minification for supported structured formats (JSON, XML).
public enum DocumentFormatter {
    /// Formats the input text according to `languageID` or auto-detected content type.
    /// - Parameters:
    ///   - text: The raw text to format.
    ///   - languageID: Identifier of the document language (e.g. "json", "xml").
    ///   - pretty: `true` to pretty-print with indentation, `false` to minify.
    ///   - indentSize: Number of spaces for indentation when `pretty` is true.
    /// - Returns: Formatted text string, or `nil` if formatting failed or format is unsupported.
    public static func format(
        text: String,
        languageID: String?,
        pretty: Bool = true,
        indentSize: Int = 2,
    ) -> String? {
        try? formatResult(text: text, languageID: languageID, pretty: pretty, indentSize: indentSize).get()
    }

    /// Formats the input text returning a `Result` with detailed `FormatError` on failure.
    public static func formatResult(
        text: String,
        languageID: String?,
        pretty: Bool = true,
        indentSize: Int = 2,
    ) -> Result<String, FormatError> {
        let lang = languageID?.lowercased() ?? ""
        Swift.print("[Meridian Debug] DocumentFormatter.formatResult triggered. lang='\(lang)', textLen=\(text.count)")

        if lang.contains("json") {
            return formatJSONResult(text: text, pretty: pretty, indentSize: indentSize)
        } else if lang.contains("xml") || lang.contains("plist") || lang.contains("svg") || lang.contains("html") {
            return formatXMLResult(text: text, pretty: pretty, indentSize: indentSize)
        }

        // Auto-detection fallback based on content prefix
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            Swift.print("[Meridian Debug] DocumentFormatter: Auto-detected JSON content")
            return formatJSONResult(text: text, pretty: pretty, indentSize: indentSize)
        } else if trimmed.hasPrefix("<") {
            Swift.print("[Meridian Debug] DocumentFormatter: Auto-detected XML content")
            return formatXMLResult(text: text, pretty: pretty, indentSize: indentSize)
        }

        Swift.print("[Meridian Debug] DocumentFormatter: Unsupported language or format (lang='\(lang)')")
        return .failure(.unsupportedLanguage(lang.isEmpty ? "unknown" : lang))
    }

    private static func formatJSONResult(text: String, pretty: Bool, indentSize: Int) -> Result<String, FormatError> {
        guard let data = text.data(using: .utf8) else {
            return .failure(.syntaxError("Unable to encode text to UTF-8"))
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            var options: JSONSerialization.WritingOptions = [.sortedKeys]
            if pretty {
                options.insert(.prettyPrinted)
            }
            let outputData = try JSONSerialization.data(withJSONObject: jsonObject, options: options)
            guard var outputString = String(data: outputData, encoding: .utf8) else {
                return .failure(.syntaxError("Unable to decode JSON output to String"))
            }
            if pretty, indentSize != 4 {
                let indentSpaces = String(repeating: " ", count: indentSize)
                outputString = outputString.replacingOccurrences(of: "    ", with: indentSpaces)
            }
            return .success(outputString)
        } catch {
            return .failure(.syntaxError(error.localizedDescription))
        }
    }

    private static func formatXMLResult(text: String, pretty: Bool, indentSize: Int) -> Result<String, FormatError> {
        do {
            let xmlDoc = try XMLDocument(xmlString: text, options: [.nodePreserveAll])
            var options: XMLNode.Options = []
            if pretty {
                options.insert(.nodePrettyPrint)
            }
            let outputString = xmlDoc.xmlString(options: options)
            if pretty, indentSize != 2 {
                let defaultIndent = "  "
                let indentSpaces = String(repeating: " ", count: indentSize)
                return .success(outputString.replacingOccurrences(of: defaultIndent, with: indentSpaces))
            }
            return .success(outputString)
        } catch {
            return .failure(.syntaxError(error.localizedDescription))
        }
    }
}
