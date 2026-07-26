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

    /// Backward-compatible convenience init for call sites that pass lines directly
    /// (used in tests and legacy callers that don't need scroll sync).
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
            ZStack(alignment: .topLeading) {
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.4)

                // Viewport highlight rectangle
                if let range = model.visibleLineRange {
                    let lineH: CGFloat = 3
                    let clampedStart = CGFloat(range.lowerBound - 1) * lineH
                    let clampedHeight = CGFloat(range.upperBound - range.lowerBound + 1) * lineH
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: geometry.size.width - 8, height: clampedHeight)
                        .offset(
                            x: 4,
                            y: min(4 + clampedStart, geometry.size.height - clampedHeight),
                        )
                        .animation(.easeInOut(duration: 0.08), value: range.lowerBound)
                }

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.lines.prefix(400).enumerated()), id: \.offset) { _, line in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(
                                width: min(geometry.size.width * 0.8, CGFloat(max(4, line.count * 2))),
                                height: 2,
                            )
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = max(0, min(1, value.location.y / max(1, geometry.size.height)))
                        let targetLine = Int(ratio * CGFloat(max(1, model.lines.count)))
                        onSelectLine?(targetLine)
                    },
            )
        }
        .frame(width: 80)
    }
}
