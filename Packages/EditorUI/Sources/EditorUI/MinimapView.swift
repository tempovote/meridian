import SwiftUI

/// High-performance miniature overview of document lines with visible viewport indicator rectangle.
public struct MinimapView: View {
    public let lines: [String]
    public let visibleLineRange: ClosedRange<Int>?
    public var onSelectLine: ((Int) -> Void)?

    public init(
        lines: [String],
        visibleLineRange: ClosedRange<Int>? = nil,
        onSelectLine: ((Int) -> Void)? = nil,
    ) {
        self.lines = lines
        self.visibleLineRange = visibleLineRange
        self.onSelectLine = onSelectLine
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.4)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.prefix(400).enumerated()), id: \.offset) { idx, line in
                        let isVisible = visibleLineRange?.contains(idx + 1) ?? false
                        Rectangle()
                            .fill(isVisible ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: min(geometry.size.width * 0.8, CGFloat(max(4, line.count * 2))), height: 2)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = max(0, min(1, value.location.y / max(1, geometry.size.height)))
                        let targetLine = Int(ratio * CGFloat(max(1, lines.count)))
                        onSelectLine?(targetLine)
                    },
            )
        }
        .frame(width: 80)
    }
}
