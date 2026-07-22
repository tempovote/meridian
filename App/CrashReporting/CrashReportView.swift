import AppKit
import SwiftUI

/// SwiftUI View presented when an unexpected crash is detected on application launch.
struct CrashReportView: View {
    let report: DiagnosticReport
    let onDismiss: () -> Void

    @State private var copiedNoticeVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.cautionName) ?? NSImage())
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Meridian Exited Unexpectedly")
                        .font(.headline)
                    Text("An unexpected crash or termination occurred during your previous session.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("App Version:")
                        .fontWeight(.semibold)
                    Text(report.appVersion)
                    Spacer()
                    Text("macOS:")
                        .fontWeight(.semibold)
                    Text(report.osVersion)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if !report.exceptionInfo.isEmpty {
                    HStack {
                        Text("Exception:")
                            .fontWeight(.semibold)
                        Text(report.exceptionInfo)
                            .foregroundColor(.red)
                    }
                    .font(.caption)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            Text("Diagnostic Details:")
                .font(.subheadline)
                .fontWeight(.medium)

            ScrollView(.vertical) {
                Text(report.backtraceSnippet)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1),
            )
            .frame(height: 180)

            HStack(spacing: 12) {
                Button("Copy Diagnostics") {
                    copyDiagnostics()
                }

                if let githubURL = report.githubIssueURL {
                    Button("Report on GitHub") {
                        NSWorkspace.shared.open(githubURL)
                    }
                }

                if let logPath = report.logFilePath {
                    Button("View Log File") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                    }
                }

                Spacer()

                if copiedNoticeVisible {
                    Text("Copied to Clipboard!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                Button("Dismiss") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 420)
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.formattedText, forType: .string)
        withAnimation {
            copiedNoticeVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                copiedNoticeVisible = false
            }
        }
    }
}
