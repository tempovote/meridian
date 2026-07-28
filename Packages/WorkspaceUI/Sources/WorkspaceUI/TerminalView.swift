import AppKit
import SwiftUI

// MARK: - ANSI Color Support

/// A single styled run of terminal output text.
struct TerminalChunk: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

/// Strips ANSI escape sequences and returns an array of coloured chunks.
private func parseANSI(_ raw: String) -> [TerminalChunk] {
    // Regex: ESC [ … m sequences
    var chunks: [TerminalChunk] = []
    var current = ""
    var currentColor = Color.primary
    var idx = raw.startIndex

    while idx < raw.endIndex {
        let nextIdx = raw.index(after: idx)
        let isEscSeq = raw[idx] == "\u{1B}" && nextIdx < raw.endIndex && raw[nextIdx] == "["
        if isEscSeq {
            if !current.isEmpty {
                chunks.append(TerminalChunk(text: current, color: currentColor))
                current = ""
            }
            // Find closing 'm'
            let seqStart = raw.index(idx, offsetBy: 2)
            if let mIdx = raw[seqStart...].firstIndex(of: "m") {
                let codes = raw[seqStart ..< mIdx].split(separator: ";")
                currentColor = ansiColor(from: codes.map { Int($0) ?? 0 }, fallback: currentColor)
                idx = raw.index(after: mIdx)
            } else {
                idx = raw.index(after: idx)
            }
        } else {
            current.append(raw[idx])
            idx = raw.index(after: idx)
        }
    }
    if !current.isEmpty {
        chunks.append(TerminalChunk(text: current, color: currentColor))
    }
    return chunks.isEmpty ? [TerminalChunk(text: raw, color: .primary)] : chunks
}

private let ansiStandardColors: [Int: Color] = [
    0: .primary,
    30: .black,
    31: Color(nsColor: NSColor.systemRed),
    32: Color(nsColor: NSColor.systemGreen),
    33: Color(nsColor: NSColor.systemYellow),
    34: Color(nsColor: NSColor.systemBlue),
    35: Color(nsColor: NSColor.systemPurple),
    36: Color(nsColor: NSColor.systemTeal),
    37: Color(nsColor: NSColor.labelColor),
    90: .secondary,
    91: Color(nsColor: NSColor.systemOrange),
    92: Color(nsColor: NSColor.systemGreen).opacity(0.8),
    93: Color(nsColor: NSColor.systemYellow).opacity(0.85),
    94: Color(nsColor: NSColor.systemIndigo),
    95: Color(nsColor: NSColor.systemPink),
    96: Color(nsColor: NSColor.systemCyan),
    97: .primary,
]

private func ansiColor(from codes: [Int], fallback: Color) -> Color {
    for code in codes {
        if code == 1 {
            continue
        } // bold — keep existing colour
        if let mapped = ansiStandardColors[code] {
            return mapped
        }
    }
    return fallback
}

// MARK: - Session Persistence

private extension String {
    /// UserDefaults key for persisting terminal working dir for a document URL.
    static func terminalDirKey(for documentURL: URL?) -> String {
        guard let url = documentURL else { return "TerminalWorkDir.__untitled__" }
        return "TerminalWorkDir.\(url.path.hashValue)"
    }
}

// MARK: - Custom Text Field

struct CustomTerminalTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onTab: () -> Void

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTerminalTextField

        init(_ parent: CustomTerminalTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.placeholderString = "Run command..."
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

// MARK: - Terminal View

/// Integrated interactive terminal view for running shell commands.
public struct TerminalView: View {
    /// The file URL of the document this terminal is attached to; used for
    /// session persistence of the working directory.
    public var documentURL: URL?

    @State private var inputCommand: String = ""
    @State private var outputLines: [[TerminalChunk]] = []
    @State private var workingDirectory: String = FileManager.default.currentDirectoryPath

    public init(documentURL: URL? = nil) {
        self.documentURL = documentURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            outputArea
            Divider()
            inputBar
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear { restoreSession() }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundColor(.accentColor)
                Text("Terminal — zsh")
                    .font(.headline)
            }

            Spacer()

            Text(workingDirectory)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)

            Button("Clear") {
                outputLines.removeAll()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Output Area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(outputLines.enumerated()), id: \.offset) { idx, chunks in
                        HStack(spacing: 0) {
                            ForEach(chunks) { chunk in
                                Text(chunk.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(chunk.color)
                            }
                            Spacer(minLength: 0)
                        }
                        .id(idx)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 100, idealHeight: 240, maxHeight: .infinity)
            .onChange(of: outputLines.count) {
                if let lastIdx = outputLines.indices.last {
                    proxy.scrollTo(lastIdx, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)

            CustomTerminalTextField(
                text: $inputCommand,
                onSubmit: executeCurrentCommand,
                onTab: handleTabCompletion,
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: Session Persistence

    /// Where a terminal panel starts when no session was previously saved
    /// for `documentURL` (or the saved directory no longer exists): the
    /// document's own containing folder, or home for an untitled document.
    /// The app's process working directory — whatever LaunchServices left
    /// it at for a GUI launch, typically "/" — is never a sensible prompt.
    static func fallbackWorkingDirectory(documentURL: URL?) -> String {
        documentURL?.deletingLastPathComponent().path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func restoreSession() {
        let key = String.terminalDirKey(for: documentURL)
        let saved = UserDefaults.standard.string(forKey: key)
        if let saved, FileManager.default.fileExists(atPath: saved) {
            workingDirectory = saved
            appendLine("Resumed session at \(saved)", color: .secondary)
        } else {
            workingDirectory = Self.fallbackWorkingDirectory(documentURL: documentURL)
            appendLine("Meridian Embedded Terminal (zsh)", color: .accentColor)
            appendLine("Type a command and press Enter...", color: .secondary)
        }
    }

    private func persistSession() {
        let key = String.terminalDirKey(for: documentURL)
        UserDefaults.standard.set(workingDirectory, forKey: key)
    }

    // MARK: Tab Completion

    private func handleTabCompletion() {
        let currentText = inputCommand
        let components = currentText.components(separatedBy: " ")
        guard let lastToken = components.last else { return }

        let pathURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent(lastToken)
        let parentDir = lastToken.contains("/")
            ? pathURL.deletingLastPathComponent()
            : URL(fileURLWithPath: workingDirectory)
        let prefix = lastToken.contains("/") ? pathURL.lastPathComponent : lastToken

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: parentDir.path)
            let matches = contents.filter { $0.hasPrefix(prefix) && !$0.hasPrefix(".") }

            if matches.count == 1, let match = matches.first {
                var newComponents = components
                let basePath = lastToken.contains("/")
                    ? (lastToken as NSString).deletingLastPathComponent + "/" : ""
                let targetPath = parentDir.appendingPathComponent(match).path
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir)
                let completedToken = basePath + match + (isDir.boolValue ? "/" : " ")
                newComponents[newComponents.count - 1] = completedToken
                inputCommand = newComponents.joined(separator: " ")
            } else if matches.count > 1 {
                appendLine(matches.joined(separator: "   "), color: .secondary)
                if let common = commonPrefix(of: matches), common.count > prefix.count {
                    var newComponents = components
                    let basePath = lastToken.contains("/")
                        ? (lastToken as NSString).deletingLastPathComponent + "/" : ""
                    newComponents[newComponents.count - 1] = basePath + common
                    inputCommand = newComponents.joined(separator: " ")
                }
            }
        } catch {
            // Ignore search errors
        }
    }

    private func commonPrefix(of strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        var res = ""
        for (idx, char) in first.enumerated() {
            if strings.allSatisfy({ idx < $0.count && $0[$0.index($0.startIndex, offsetBy: idx)] == char }) {
                res.append(char)
            } else {
                break
            }
        }
        return res
    }

    // MARK: Command Execution

    private func executeCurrentCommand() {
        let cmd = inputCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        appendLine("$ \(cmd)", color: .accentColor)
        inputCommand = ""

        if cmd.hasPrefix("cd ") {
            let dirArg = String(cmd.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            let targetURL = URL(fileURLWithPath: dirArg, relativeTo: URL(fileURLWithPath: workingDirectory))
                .standardized
            if FileManager.default.fileExists(atPath: targetURL.path) {
                workingDirectory = targetURL.path
                persistSession()
            } else {
                appendLine("cd: no such file or directory: \(dirArg)", color: Color(nsColor: NSColor.systemRed))
            }
            return
        }

        let dir = workingDirectory
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
                if !out.isEmpty {
                    DispatchQueue.main.async {
                        appendLine(out, color: .primary)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    appendLine("Error: \(error.localizedDescription)", color: Color(nsColor: NSColor.systemRed))
                }
            }
        }
    }

    // MARK: Helpers

    private func appendLine(_ text: String, color: Color = .primary) {
        outputLines.append(parseANSI(text).map {
            TerminalChunk(text: $0.text, color: $0.color == .primary ? color : $0.color)
        })
    }
}
