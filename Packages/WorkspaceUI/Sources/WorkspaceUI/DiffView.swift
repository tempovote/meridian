import SearchKit
import SwiftUI

/// Display mode options for DiffView.
public enum DiffViewMode: String, CaseIterable, Identifiable, Sendable {
    case sideBySide = "Side by Side"
    case unified = "Unified"

    public var id: String {
        rawValue
    }
}

/// SwiftUI view rendering side-by-side and unified diffs.
public struct DiffView: View {
    public let result: DiffResult
    @State private var mode: DiffViewMode = .sideBySide

    public init(result: DiffResult, initialMode: DiffViewMode = .sideBySide) {
        self.result = result
        _mode = State(initialValue: initialMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text(result.leftName)
                    .font(.headline)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    if result.addedCount > 0 {
                        Text("+\(result.addedCount)")
                            .font(.caption.monospaced().bold())
                            .foregroundColor(.green)
                    }
                    if result.deletedCount > 0 {
                        Text("-\(result.deletedCount)")
                            .font(.caption.monospaced().bold())
                            .foregroundColor(.red)
                    }
                    if result.modifiedCount > 0 {
                        Text("~\(result.modifiedCount)")
                            .font(.caption.monospaced().bold())
                            .foregroundColor(.orange)
                    }
                    if result.addedCount == 0, result.deletedCount == 0, result.modifiedCount == 0 {
                        Text("Identical")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Picker("Mode", selection: $mode) {
                    ForEach(DiffViewMode.allCases) { viewMode in
                        Text(viewMode.rawValue).tag(viewMode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text(result.rightName)
                    .font(.headline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var contentArea: some View {
        switch mode {
        case .sideBySide:
            sideBySideView
        case .unified:
            unifiedView
        }
    }

    private var sideBySideView: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
                ForEach(result.pairs) { pair in
                    HStack(spacing: 0) {
                        sideCell(line: pair.left, isLeft: true)
                        Divider()
                        sideCell(line: pair.right, isLeft: false)
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    private func sideCell(line: DiffLine, isLeft: Bool) -> some View {
        HStack(spacing: 8) {
            Text(line.lineNumber.map { String($0) } ?? "")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(cellBackgroundColor(kind: line.kind))
    }

    private var unifiedView: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 0) {
                ForEach(result.pairs) { pair in
                    if pair.left.kind == .deleted {
                        unifiedRow(lineNumber: pair.left.lineNumber, symbol: "-", text: pair.left.text, kind: .deleted)
                    } else if pair.right.kind == .added {
                        unifiedRow(lineNumber: pair.right.lineNumber, symbol: "+", text: pair.right.text, kind: .added)
                    } else if pair.left.kind == .modified || pair.right.kind == .modified {
                        if !pair.left.text.isEmpty {
                            unifiedRow(
                                lineNumber: pair.left.lineNumber,
                                symbol: "-",
                                text: pair.left.text,
                                kind: .deleted,
                            )
                        }
                        if !pair.right.text.isEmpty {
                            unifiedRow(
                                lineNumber: pair.right.lineNumber,
                                symbol: "+",
                                text: pair.right.text,
                                kind: .added,
                            )
                        }
                    } else {
                        unifiedRow(
                            lineNumber: pair.right.lineNumber ?? pair.left.lineNumber,
                            symbol: " ",
                            text: pair.right.text,
                            kind: .unchanged,
                        )
                    }
                }
            }
        }
    }

    private func unifiedRow(lineNumber: Int?, symbol: String, text: String, kind: DiffLineKind) -> some View {
        HStack(spacing: 8) {
            Text(lineNumber.map { String($0) } ?? "")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            Text(symbol)
                .font(.caption.monospaced().bold())
                .foregroundColor(symbolColor(kind: kind))
                .frame(width: 12)

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(cellBackgroundColor(kind: kind))
    }

    private func symbolColor(kind: DiffLineKind) -> Color {
        switch kind {
        case .added: .green
        case .deleted: .red
        case .modified: .orange
        case .unchanged: .secondary
        }
    }

    private func cellBackgroundColor(kind: DiffLineKind) -> Color {
        switch kind {
        case .added: Color.green.opacity(0.18)
        case .deleted: Color.red.opacity(0.18)
        case .modified: Color.orange.opacity(0.18)
        case .unchanged: Color.clear
        }
    }
}
