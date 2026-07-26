import AppKit
import SwiftUI

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

/// Integrated interactive terminal view for running shell commands.
public struct TerminalView: View {
    @State private var inputCommand: String = ""
    @State private var outputLogs: [String] = ["Meridian Embedded Terminal (zsh)", "Type a command and press Enter..."]
    @State private var workingDirectory: String = FileManager.default.currentDirectoryPath

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            outputArea
            Divider()
            inputBar
        }
        .background(Color(NSColor.textBackgroundColor))
    }

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
                outputLogs.removeAll()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(outputLogs.enumerated()), id: \.offset) { idx, log in
                        Text(log)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(log.hasPrefix("$") ? .accentColor : .primary)
                            .id(idx)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: outputLogs.count) {
                if let lastIdx = outputLogs.indices.last {
                    proxy.scrollTo(lastIdx, anchor: .bottom)
                }
            }
        }
    }

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

    private func handleTabCompletion() {
        let currentText = inputCommand
        let components = currentText.components(separatedBy: " ")
        guard let lastToken = components.last else { return }

        let pathURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent(lastToken)
        let parentDir = lastToken.contains("/") ? pathURL
            .deletingLastPathComponent() : URL(fileURLWithPath: workingDirectory)
        let prefix = lastToken.contains("/") ? pathURL.lastPathComponent : lastToken

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: parentDir.path)
            let matches = contents.filter { $0.hasPrefix(prefix) && !$0.hasPrefix(".") }

            if matches.count == 1, let match = matches.first {
                var newComponents = components
                let basePath = lastToken.contains("/") ? (lastToken as NSString).deletingLastPathComponent + "/" : ""
                let targetPath = parentDir.appendingPathComponent(match).path
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDir)
                let completedToken = basePath + match + (isDir.boolValue ? "/" : " ")
                newComponents[newComponents.count - 1] = completedToken
                inputCommand = newComponents.joined(separator: " ")
            } else if matches.count > 1 {
                outputLogs.append(matches.joined(separator: "   "))
                if let common = commonPrefix(of: matches), common.count > prefix.count {
                    var newComponents = components
                    let isPath = lastToken.contains("/")
                    let basePath = isPath ? (lastToken as NSString).deletingLastPathComponent + "/" : ""
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

    private func executeCurrentCommand() {
        let cmd = inputCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        outputLogs.append("$ \(cmd)")
        inputCommand = ""

        if cmd.hasPrefix("cd ") {
            let dirArg = String(cmd.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            let targetURL = URL(fileURLWithPath: dirArg, relativeTo: URL(fileURLWithPath: workingDirectory))
                .standardized
            if FileManager.default.fileExists(atPath: targetURL.path) {
                workingDirectory = targetURL.path
            } else {
                outputLogs.append("cd: no such file or directory: \(dirArg)")
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
                if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines), !out.isEmpty {
                    DispatchQueue.main.async {
                        outputLogs.append(out)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    outputLogs.append("Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
