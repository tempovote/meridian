import Foundation

/// Represents diagnostic details gathered after an application crash.
struct DiagnosticReport: Sendable {
    let timestamp: String
    let appVersion: String
    let osVersion: String
    let architecture: String
    let exceptionInfo: String
    let backtraceSnippet: String
    let logFilePath: String?

    /// Generates a clean formatted report for copying or viewing.
    var formattedText: String {
        let logLine = logFilePath.map { "- **Log File:** \($0)" } ?? ""
        return [
            "### Meridian Crash Report Diagnostics",
            "- **Timestamp:** \(timestamp)",
            "- **App Version:** \(appVersion)",
            "- **macOS Version:** \(osVersion)",
            "- **Architecture:** \(architecture)",
            "- **Exception Info:** \(exceptionInfo)",
            logLine,
            "",
            "### Stack Trace / Diagnostics",
            "```",
            backtraceSnippet,
            "```",
        ].joined(separator: "\n")
    }

    /// Constructs a pre-filled GitHub issue URL.
    var githubIssueURL: URL? {
        let issueTitle = "Crash Report: \(exceptionInfo)"
        let issueBody = [
            "## Description",
            "Meridian exited unexpectedly.",
            "",
            "## Diagnostics",
            "- **App Version:** \(appVersion)",
            "- **macOS Version:** \(osVersion)",
            "- **Architecture:** \(architecture)",
            "- **Exception:** \(exceptionInfo)",
            "",
            "<details>",
            "<summary>Stack Trace / System Diagnostic Snippet</summary>",
            "",
            "```",
            backtraceSnippet,
            "```",
            "</details>",
        ].joined(separator: "\n")

        var components = URLComponents(string: "https://github.com/tempovote/meridian/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "body", value: issueBody),
            URLQueryItem(name: "labels", value: "bug"),
        ]
        return components?.url
    }
}

/// Utility for discovering and parsing local macOS crash diagnostic reports.
enum DiagnosticReportCollector {
    /// Collects the latest crash report for Meridian or generates a system diagnostic report fallback.
    static func collectLatestReport() -> DiagnosticReport {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
            let arch = "Apple Silicon (arm64)"
        #else
            let arch = "x86_64"
        #endif

        if let res = findLatestDiagnosticFile() {
            if let content = try? String(contentsOf: res.url, encoding: .utf8) {
                let (exceptionInfo, snippet) = parseReportContent(content)
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .medium

                return DiagnosticReport(
                    timestamp: df.string(from: res.date),
                    appVersion: appVersion,
                    osVersion: osVersion,
                    architecture: arch,
                    exceptionInfo: exceptionInfo,
                    backtraceSnippet: snippet,
                    logFilePath: res.url.path,
                )
            }
        }

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium

        let fallbackSnippet = [
            "The previous session ended unexpectedly.",
            "No system crash log was found in ~/Library/Logs/DiagnosticReports/.",
        ].joined(separator: "\n")

        return DiagnosticReport(
            timestamp: df.string(from: Date()),
            appVersion: appVersion,
            osVersion: osVersion,
            architecture: arch,
            exceptionInfo: "Abnormal Termination (No .ips diagnostic log found)",
            backtraceSnippet: fallbackSnippet,
            logFilePath: nil,
        )
    }

    /// Finds the newest `.ips` or `.crash` diagnostic file for Meridian.
    private static func findLatestDiagnosticFile() -> (url: URL, date: Date)? {
        let fileManager = FileManager.default
        guard let diagnosticDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/DiagnosticReports"),
            let files = try? fileManager.contentsOfDirectory(
                at: diagnosticDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
            )
        else { return nil }

        var latestFileUrl: URL?
        var latestDate: Date = .distantPast

        for fileUrl in files {
            let filename = fileUrl.lastPathComponent
            let isMatch = filename.hasPrefix("Meridian") && (filename.hasSuffix(".ips") || filename.hasSuffix(".crash"))
            if isMatch {
                let values = try? fileUrl.resourceValues(forKeys: [.contentModificationDateKey])
                let modDate = values?.contentModificationDate ?? .distantPast
                if modDate > latestDate {
                    latestDate = modDate
                    latestFileUrl = fileUrl
                }
            }
        }

        guard let latestFileUrl else { return nil }
        return (latestFileUrl, latestDate)
    }

    /// Parses macOS IPS / crash log content to extract exception info and a backtrace snippet.
    private static func parseReportContent(_ content: String) -> (exception: String, snippet: String) {
        let lines = content.components(separatedBy: .newlines)
        var exceptionType = "Unknown Exception"
        var snippetLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }

            let hasExc = trimmed.contains("\"exception\"") || trimmed.contains("\"termination\"") || trimmed
                .contains("\"bug_type\"")
            if hasExc, let data = trimmed.data(using: .utf8) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    exceptionType = extractExceptionType(from: json)
                }
            }

            if snippetLines.count < 30 {
                snippetLines.append(line)
            }
        }

        let snippet = snippetLines.prefix(25).joined(separator: "\n")
        return (exceptionType, snippet.isEmpty ? content : snippet)
    }

    private static func extractExceptionType(from json: [String: Any]) -> String {
        var result = "Unknown Exception"
        if let bugType = json["bug_type"] as? String {
            result = "Crash (\(bugType))"
        }
        if let exc = json["exception"] as? [String: Any], let type = exc["type"] as? String {
            result = type
        }
        if let term = json["termination"] as? [String: Any] {
            if let code = term["code"] as? Int, let ns = term["namespace"] as? String {
                result += " [\(ns) code \(code)]"
            }
        }
        return result
    }
}
