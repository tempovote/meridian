import DocumentCore
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
    public var currentEncoding: TextEncoding?
    public var currentIncludeBOM: Bool
    public var onSelectEncoding: ((TextEncoding, Bool) -> Void)?
    public var onReopenWithEncoding: ((TextEncoding) -> Void)?

    public init(
        viewModel: EditorViewModel,
        encodingName: String = "UTF-8",
        lineEndingName: String = "LF",
        fileSizeString: String? = nil,
        currentEncoding: TextEncoding? = nil,
        currentIncludeBOM: Bool = false,
        onSelectEncoding: ((TextEncoding, Bool) -> Void)? = nil,
        onReopenWithEncoding: ((TextEncoding) -> Void)? = nil,
    ) {
        self.viewModel = viewModel
        self.encodingName = encodingName
        self.lineEndingName = lineEndingName
        self.fileSizeString = fileSizeString
        self.currentEncoding = currentEncoding
        self.currentIncludeBOM = currentIncludeBOM
        self.onSelectEncoding = onSelectEncoding
        self.onReopenWithEncoding = onReopenWithEncoding
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
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
                    Menu {
                        Toggle("Save with BOM", isOn: Binding(
                            get: { currentIncludeBOM },
                            set: { newValue in
                                if let enc = currentEncoding {
                                    onSelectEncoding?(enc, newValue)
                                }
                            },
                        ))

                        Divider()

                        Menu("Reopen with Encoding...") {
                            ForEach(TextEncoding.commonEncodings, id: \.self) { enc in
                                Button(enc.displayName) {
                                    onReopenWithEncoding?(enc)
                                }
                            }
                        }

                        Divider()

                        ForEach(TextEncoding.commonEncodings, id: \.self) { enc in
                            Button(
                                action: {
                                    onSelectEncoding?(enc, currentIncludeBOM)
                                },
                                label: {
                                    if enc == currentEncoding {
                                        Text("✓ \(enc.displayName)")
                                    } else {
                                        Text(enc.displayName)
                                    }
                                },
                            )
                        }
                    } label: {
                        Text(encodingName)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

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
