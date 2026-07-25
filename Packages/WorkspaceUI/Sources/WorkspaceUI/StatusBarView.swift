import EditorUI
import SwiftUI

/// Low-profile SwiftUI status bar (height 22pt) displayed at the bottom of
/// document windows, presenting cursor coordinates, selection size,
/// line count, encoding, line endings, and file size.
public struct StatusBarView: View {
    public var viewModel: EditorViewModel
    public var encodingName: String
    public var lineEndingName: String
    public var fileSizeString: String?
    public var onToggleSidebar: (() -> Void)?

    public init(
        viewModel: EditorViewModel,
        encodingName: String = "UTF-8",
        lineEndingName: String = "LF",
        fileSizeString: String? = nil,
        onToggleSidebar: (() -> Void)? = nil,
    ) {
        self.viewModel = viewModel
        self.encodingName = encodingName
        self.lineEndingName = lineEndingName
        self.fileSizeString = fileSizeString
        self.onToggleSidebar = onToggleSidebar
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                if let onToggleSidebar {
                    Button(action: onToggleSidebar) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Sidebar (⌘B)")
                }

                // Line / Column & Selection
                HStack(spacing: 8) {
                    let pos = viewModel.currentCaretLineColumn
                    Text("Ln \(pos.line), Col \(pos.column)")

                    if viewModel.selectionCharacterCount > 0 {
                        Text("(\(viewModel.selectionCharacterCount) selected)")
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))

                    Text("\(viewModel.lineCount) lines")
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Metadata (Encoding, Line Endings, Size)
                HStack(spacing: 12) {
                    Text(encodingName)
                    Text(lineEndingName)
                    if let fileSizeString {
                        Text(fileSizeString)
                    }
                }
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
