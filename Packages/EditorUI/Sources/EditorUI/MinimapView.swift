import SwiftUI

/// Observable model that bridges AppKit scroll events to the SwiftUI MinimapView.
///
/// Holds the length of each mark to draw rather than the document's text: the
/// view derives a mark's width from the line's character count and ignores
/// everything else about it, so retaining one `String` per line was dead
/// weight that scaled with the document.
///
/// Above ``perLineLimit`` lines the marks are bucketed instead, bounding both
/// storage and per-frame draw work. Below it the mapping is one mark per line,
/// which reproduces the previous rendering exactly — the point at which
/// bucketing starts is far past where an 80-point-wide view could resolve
/// individual lines anyway.
public final class MinimapViewModel: ObservableObject {
    /// Documents at or below this many lines keep one mark per line.
    public static let perLineLimit = 5000
    /// Number of buckets used once ``perLineLimit`` is exceeded.
    public static let sampleCount = 400

    /// Number of lines in the document. Distinct from `markLengths.count`
    /// once bucketing kicks in, and the value the viewport indicator maps
    /// scroll position against.
    @Published public private(set) var lineCount: Int
    /// One entry per drawn mark, in points, before the view clamps it to the
    /// minimap's width. Zero means "draw nothing here" — a blank line.
    @Published public private(set) var markLengths: [Double]
    @Published public var visibleLineRange: ClosedRange<Int>?

    /// Length in points of the mark drawn for a line of `count` characters.
    /// Kept as one function so the per-line and bucketed paths cannot drift.
    static func markLength(forCharacterCount count: Int) -> Double {
        Double(max(4, count * 2))
    }

    public init(lines: [String], visibleLineRange: ClosedRange<Int>? = nil) {
        lineCount = 0
        markLengths = []
        self.visibleLineRange = visibleLineRange
        update(fromLines: lines)
    }

    /// Recomputes the marks from the document's lines.
    public func update(fromLines lines: [String]) {
        lineCount = lines.count
        guard !lines.isEmpty else {
            markLengths = []
            return
        }
        guard lines.count > Self.perLineLimit else {
            markLengths = lines.map(Self.markLength(forLine:))
            return
        }
        // Each bucket takes the longest line it covers rather than an
        // average, so an isolated long line in a sparse region stays visible.
        var buckets = [Double](repeating: 0, count: Self.sampleCount)
        for (index, line) in lines.enumerated() {
            let length = Self.markLength(forLine: line)
            guard length > 0 else { continue }
            let bucket = min(Self.sampleCount - 1, index * Self.sampleCount / lines.count)
            buckets[bucket] = max(buckets[bucket], length)
        }
        markLengths = buckets
    }

    /// Zero for a blank line, so the view can skip it. Checked without
    /// `trimmingCharacters`, which would allocate a `String` per line.
    private static func markLength(forLine line: String) -> Double {
        guard !line.allSatisfy(\.isWhitespace) else { return 0 }
        return markLength(forCharacterCount: line.count)
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
            let totalLines = max(1, model.lineCount)
            let height = geometry.size.height
            let width = geometry.size.width

            ZStack(alignment: .topLeading) {
                Color(NSColor.controlBackgroundColor)
                    .opacity(0.4)

                // Canvas rendering every mark the model holds — one per line
                // for an ordinary document, one per bucket for a huge one.
                Canvas { context, size in
                    let markCount = model.markLengths.count
                    guard markCount > 0 else { return }
                    let rowSpacing = size.height / CGFloat(markCount)
                    for (idx, markLength) in model.markLengths.enumerated() where markLength > 0 {
                        let lineY = (CGFloat(idx) / CGFloat(markCount)) * size.height
                        let lineWidth = min(size.width * 0.75, CGFloat(markLength))
                        let lineH = max(1.0, min(2.5, rowSpacing * 0.8))

                        let rect = CGRect(
                            x: 4,
                            y: lineY,
                            width: lineWidth,
                            height: lineH,
                        )
                        context.fill(Path(rect), with: .color(Color.secondary.opacity(0.45)))
                    }
                }

                // Viewport indicator matching page proportions (min height 44pt for 1-page representation)
                if let range = model.visibleLineRange {
                    let firstLine = CGFloat(max(1, min(totalLines, range.lowerBound)))
                    let lastLine = CGFloat(max(Int(firstLine), min(totalLines, range.upperBound)))
                    let visibleCount = max(1, lastLine - firstLine + 1)

                    let rawViewportRatio = visibleCount / CGFloat(totalLines)
                    let rectH = max(44, min(height, rawViewportRatio * height))

                    let maxScrollableLines = max(1, CGFloat(totalLines) - visibleCount)
                    let scrollRatio = (firstLine - 1) / maxScrollableLines
                    let clampedRatio = max(0, min(1, scrollRatio))
                    let topY = clampedRatio * (height - rectH)

                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5),
                        )
                        .frame(width: max(0, width - 4), height: rectH)
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
