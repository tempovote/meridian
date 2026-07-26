import SwiftUI

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
        .frame(minHeight: 200)
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

            TextField("Run command...", text: $inputCommand)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    executeCurrentCommand()
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func executeCurrentCommand() {
        let cmd = inputCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        outputLogs.append("$ \(cmd)")
        inputCommand = ""

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
