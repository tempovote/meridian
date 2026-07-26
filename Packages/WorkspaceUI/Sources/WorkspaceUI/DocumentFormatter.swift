import DocumentCore
import Foundation

/// Provides code formatting and minification for supported structured formats (JSON, XML).
public enum DocumentFormatter {
    /// Formats the input text according to `languageID`.
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
        guard let languageID = languageID?.lowercased() else { return nil }
        switch languageID {
        case "json":
            return formatJSON(text: text, pretty: pretty, indentSize: indentSize)
        case "xml":
            return formatXML(text: text, pretty: pretty, indentSize: indentSize)
        default:
            return nil
        }
    }

    private static func formatJSON(text: String, pretty: Bool, indentSize: Int) -> String? {
        guard let data = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }

        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }

        guard let outputData = try? JSONSerialization.data(withJSONObject: jsonObject, options: options),
              var outputString = String(data: outputData, encoding: .utf8)
        else {
            return nil
        }

        if pretty, indentSize != 4 {
            let indentSpaces = String(repeating: " ", count: indentSize)
            outputString = outputString.replacingOccurrences(of: "    ", with: indentSpaces)
        }

        return outputString
    }

    private static func formatXML(text: String, pretty: Bool, indentSize: Int) -> String? {
        guard let xmlDoc = try? XMLDocument(xmlString: text, options: [.nodePreserveAll]) else {
            return nil
        }

        var options: XMLNode.Options = []
        if pretty {
            options.insert(.nodePrettyPrint)
        }

        let outputString = xmlDoc.xmlString(options: options)
        if pretty, indentSize != 2 {
            let defaultIndent = "  "
            let indentSpaces = String(repeating: " ", count: indentSize)
            return outputString.replacingOccurrences(of: defaultIndent, with: indentSpaces)
        }

        return outputString
    }
}
