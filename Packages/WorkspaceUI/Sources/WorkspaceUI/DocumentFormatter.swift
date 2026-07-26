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
        let lang = languageID?.lowercased() ?? ""
        Swift.print("[Meridian Debug] DocumentFormatter.format triggered. lang='\(lang)', textLen=\(text.count)")

        if lang.contains("json") {
            return formatJSON(text: text, pretty: pretty, indentSize: indentSize)
        } else if lang.contains("xml") || lang.contains("plist") || lang.contains("svg") || lang.contains("html") {
            return formatXML(text: text, pretty: pretty, indentSize: indentSize)
        }

        // Auto-detection fallback based on content prefix
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            Swift.print("[Meridian Debug] DocumentFormatter: Auto-detected JSON content")
            return formatJSON(text: text, pretty: pretty, indentSize: indentSize)
        } else if trimmed.hasPrefix("<") {
            Swift.print("[Meridian Debug] DocumentFormatter: Auto-detected XML content")
            return formatXML(text: text, pretty: pretty, indentSize: indentSize)
        }

        Swift.print(
            "[Meridian Debug] DocumentFormatter: Unsupported language or format (lang='\(lang)')",
        )
        return nil
    }

    private static func formatJSON(text: String, pretty: Bool, indentSize: Int) -> String? {
        guard let data = text.data(using: .utf8) else {
            Swift.print("[Meridian Debug] formatJSON failed: Unable to encode text to UTF-8 data")
            return nil
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            var options: JSONSerialization.WritingOptions = [.sortedKeys]
            if pretty {
                options.insert(.prettyPrinted)
            }
            let outputData = try JSONSerialization.data(withJSONObject: jsonObject, options: options)
            guard var outputString = String(data: outputData, encoding: .utf8) else {
                Swift.print("[Meridian Debug] formatJSON failed: Unable to decode JSON output data to String")
                return nil
            }
            if pretty, indentSize != 4 {
                let indentSpaces = String(repeating: " ", count: indentSize)
                outputString = outputString.replacingOccurrences(of: "    ", with: indentSpaces)
            }
            Swift.print("[Meridian Debug] formatJSON succeeded! Output length=\(outputString.count)")
            return outputString
        } catch {
            Swift.print("[Meridian Debug] formatJSON syntax parse error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func formatXML(text: String, pretty: Bool, indentSize: Int) -> String? {
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
                return outputString.replacingOccurrences(of: defaultIndent, with: indentSpaces)
            }
            Swift.print("[Meridian Debug] formatXML succeeded! Output length=\(outputString.count)")
            return outputString
        } catch {
            Swift.print("[Meridian Debug] formatXML syntax parse error: \(error.localizedDescription)")
            return nil
        }
    }
}
