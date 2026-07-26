import SwiftUI

/// Observable model that bridges AppKit scroll events to the SwiftUI MinimapView.
public final class MinimapViewModel: ObservableObject {
    @Published public var lines: [String]
    @Published public var visibleLineRange: ClosedRange<Int>?

    public init(lines: [String], visibleLineRange: ClosedRange<Int>? = nil) {
        self.lines = lines
        self.visibleLineRange = visibleLineRange
    }
}

/// High-performance miniature overview of document lines with visible viewport indicator rectangle.
public struct MinimapView: View {
    @ObservedObject public var model: MinimapViewModel
    public var onSelectLine: ((Int) -> Void)?

    public init(
        model: MinimapViewModel,
        onSelectLine: ((Int) -> Void)? = nil,
    ) {
        self.model = model
        self.onSelectLine = onSelectLine
    }

    /// Backward-compatible convenience init for callers that pass lines directly.
    public init(
        lines: [String],
        visibleLineRange: ClosedRange<Int>? = nil,
        onSelectLine: ((Int) -> Void)? = nil,
    ) {
        model = MinimapViewModel(lines: lines, visibleLineRange: visibleLineRange)
        self.onSelectLine = onSelectLine
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalLines = max(1, model.lines.count)
            let height = geometry.size.height
            let lineSpacing = height / CGFloat(totalLines)

            ZStack(alignment: .topLeading) {
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.4)

                // Mini document lines scaled proportionally to minimap track height
                ZStack(alignment: .topLeading) {
                    ForEach(Array(model.lines.prefix(350).enumerated()), id: \.offset) { idx, line in
                        let lineY = (CGFloat(idx) / CGFloat(totalLines)) * height
                        let lineWidth = min(geometry.size.width * 0.75, CGFloat(max(4, line.count * 2)))
                        let lineH = max(1, min(2.5, lineSpacing * 0.75))
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: lineWidth, height: lineH)
                            .position(x: 4 + lineWidth / 2, y: lineY + lineH / 2)
                    }
                }

                // Viewport indicator matching scrollbar proportions
                if let range = model.visibleLineRange {
                    let firstLine = CGFloat(max(1, min(totalLines, range.lowerBound)))
                    let lastLine = CGFloat(max(Int(firstLine), min(totalLines, range.upperBound)))
                    let visibleCount = max(1, lastLine - firstLine + 1)

                    let rawViewportRatio = visibleCount / CGFloat(totalLines)
                    let rectH = max(24, min(height, rawViewportRatio * height))

                    let maxScrollableLines = max(1, CGFloat(totalLines) - visibleCount)
                    let scrollRatio = (firstLine - 1) / maxScrollableLines
                    let clampedRatio = max(0, min(1, scrollRatio))
                    let topY = clampedRatio * (height - rectH)

                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1),
                        )
                        .frame(width: max(0, geometry.size.width - 4), height: rectH)
                        .offset(x: 2, y: topY)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let contentY = value.location.y
                        let ratio = max(0, min(1, contentY / max(1, height)))
                        let targetLine = Int(ratio * CGFloat(totalLines))
                        onSelectLine?(targetLine)
                    },
            )
        }
        .frame(width: 80)
    }
}
