import FileKit
import SwiftUI

/// SwiftUI view displaying raw data formatted in hex rows.
public struct HexInspectorView: View {
    public let data: Data
    public let fileName: String
    private let rows: [HexRow]

    public init(data: Data, fileName: String = "Document") {
        self.data = data
        self.fileName = fileName
        rows = HexFormatter.format(data: data)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentList
        }
        .frame(minWidth: 550, minHeight: 300)
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image("icon_hex_inspector")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(.accentColor)
                Text("Hex Inspector — \(fileName)")
                    .font(.headline)
            }

            Spacer()

            HStack(spacing: 12) {
                Text("\(data.count) Bytes")
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)

                Text("\(rows.count) Rows")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var contentList: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 16) {
                    Text("Offset")
                        .font(.caption.monospaced().bold())
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    Text("00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F")
                        .font(.caption.monospaced().bold())
                        .foregroundColor(.secondary)
                        .frame(width: 380, alignment: .leading)

                    Text("ASCII")
                        .font(.caption.monospaced().bold())
                        .foregroundColor(.secondary)
                        .frame(width: 150, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                ForEach(rows) { row in
                    HStack(spacing: 16) {
                        Text(row.offsetString)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(row.hexBytes)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(width: 380, alignment: .leading)

                        Text(row.ascii)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .frame(width: 150, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
