import AppKit
import DocumentCore

/// Self-driving benchmark: smooth scroll passes, then typing at three
/// positions. Frame times come from the view's display link; "dropped" =
/// frame delta > 1.5× the display's refresh interval.
///
/// DEVIATION (Task 5 controller amendment, binding): the brief also
/// specified a jump phase (`runJumps()`, `jump_*` output, `jump` verdict).
/// It is dropped entirely here. Task 4's jump investigation proved
/// `ViewportView.jump(toLine:)` crashes deterministically via an
/// uncatchable `NSInvalidArgumentException` inside AppKit's private
/// `NSCountableTextLocation.compare:` (see task-4-report.md / ADR 0009) —
/// there is no safe way to call it, so this driver never does.
///
/// DEVIATION (Task 5 controller amendment): typing no longer jumps to each
/// position first. The viewport is left wherever it naturally is —
/// concretely, the typing phase now runs *before* the scroll phase (see
/// `start()`), so it always measures typing with the viewport parked at
/// the document top, exactly as loaded. That makes the interpretation
/// exact: "start" (line 10) is on-screen typing cost; "middle"/"end" are
/// off-screen edit+invalidation cost (the edit still applies via
/// `applyEdit`, and the content manager still walks its invalidation path
/// down to document end — see `RopeContentManager.applyEdit` — even though
/// nothing at that line is currently laid out). The brief's per-position
/// jump + 300 ms settle is dropped along with the jump call; the 40
/// keystrokes × 30 ms cadence per position is unchanged.
///
/// INTERPRETIVE CAVEAT (carry verbatim into any report of these numbers):
/// Typing latencies may be optimistic: `RopeLocation.compare` returns
/// `.orderedSame` for AppKit-private locations in the invalidation path
/// (Task 4 forced fix), which could under-invalidate; these numbers
/// measure the code as written, not a proven-correct invalidation.
@MainActor
final class BenchmarkDriver {
    let view: ViewportView
    let scrollView: NSScrollView
    let corpusName: String
    let loadSeconds: Double
    var editOnly = false
    var scrollOnly = false
    /// Viewport-heights/second for the smooth-scroll phase. Default matches
    /// the brief's 8×. DEVIATION (Task 5 controller amendment 3): continuous
    /// small-delta scrolling is expected to be safe (Task 4's proven-working
    /// regime), but the jump investigation separately observed
    /// large-relocation deltas crash even without calling `jump`/
    /// `relocateViewport` directly (the "boundsOnly" approach in that
    /// investigation still crashed once the per-step delta got jump-sized).
    /// This is exposed as a tunable, not hardcoded, so the smoke procedure
    /// can bisect it down if 8× turns out unsafe on a real corpus — the
    /// crash velocity threshold is itself a key ADR 0009 datum. See
    /// `main.swift`'s `--scroll-velocity=<n>` flag.
    var scrollVelocityMultiplier = 8.0

    private var frameDeltas: [Double] = []
    private var lastTimestamp: CFTimeInterval?
    private var refreshInterval: Double = 1.0 / 60.0

    init(view: ViewportView, scrollView: NSScrollView, corpusName: String, loadSeconds: Double) {
        self.view = view
        self.scrollView = scrollView
        self.corpusName = corpusName
        self.loadSeconds = loadSeconds
    }

    func start() {
        let maxFPS = view.window?.screen?.maximumFramesPerSecond ?? 60
        refreshInterval = 1.0 / Double(max(maxFPS, 30))
        view.onFrame = { [weak self] timestamp, _ in
            guard let self else { return }
            if let last = lastTimestamp { frameDeltas.append(timestamp - last) }
            lastTimestamp = timestamp
        }
        Task { @MainActor in
            var scrollStats: Stats?
            var droppedPct = 0.0
            var typeStats: [String: Stats] = [:]
            // DEVIATION: typing runs before scrolling (see type-level doc
            // comment) so "viewport stays wherever it is" means "document
            // top" even when both phases run in the same invocation.
            if !scrollOnly {
                print("# phase=typing start")
                typeStats = await runTyping()
                print("# phase=typing done")
            }
            if !editOnly {
                print("# phase=scroll start velocity=\(scrollVelocityMultiplier)")
                (scrollStats, droppedPct) = await runSmoothScroll()
                print("# phase=scroll done")
            }
            report(scroll: scrollStats, dropped: droppedPct, typing: typeStats)
        }
    }

    // MARK: Phases

    /// 3 passes top→bottom→top at `scrollVelocityMultiplier`
    /// viewport-heights/second, capped at 20 s per pass (a full 1 GB pass at
    /// readable speed would take hours; the cap samples a long contiguous
    /// stretch instead).
    private func runSmoothScroll() async -> (Stats, Double) {
        frameDeltas.removeAll()
        lastTimestamp = nil
        let clip = scrollView.contentView
        let viewportH = clip.bounds.height
        let maxY = max(view.estimatedDocumentHeight - viewportH, 0)
        let velocity = viewportH * scrollVelocityMultiplier
        for pass in 0 ..< 3 {
            let down = pass % 2 == 0
            var y = down ? clip.bounds.origin.y : min(clip.bounds.origin.y, maxY)
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                y += (down ? 1 : -1) * velocity * refreshInterval
                if y < 0 || y > maxY { break }
                clip.setBoundsOrigin(NSPoint(x: 0, y: y))
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
        let stats = Stats(samples: frameDeltas.map { $0 * 1000 })
        let dropped = frameDeltas.isEmpty ? 0.0 :
            Double(frameDeltas.count(where: { $0 > refreshInterval * 1.5 })) / Double(frameDeltas.count) * 100
        return (stats, dropped)
    }

    /// 40 keystrokes at each of three byte positions (start/middle/end);
    /// latency = applyEdit + immediate viewport re-layout, which is the
    /// synchronous cost a keystroke pays before the next frame can present.
    /// DEVIATION: no `jump(toLine:)` call before each position (forbidden,
    /// see type-level doc comment) — the viewport is left at document top
    /// for the entire phase, so "middle"/"end" measure off-screen
    /// edit+invalidation cost, not on-screen typing cost.
    private func runTyping() async -> [String: Stats] {
        var results: [String: Stats] = [:]
        let buffer = view.contentManager.buffer
        let positions: [(String, ByteOffset)] = [
            ("start", buffer.byteRange(ofLine: min(10, buffer.lineCount - 1)).lowerBound),
            ("middle", buffer.byteRange(ofLine: buffer.lineCount / 2).lowerBound),
            ("end", buffer.byteRange(ofLine: max(buffer.lineCount - 10, 0)).lowerBound),
        ]
        for (name, byte) in positions {
            var latencies: [Double] = []
            var caret = byte
            for i in 0 ..< 40 {
                let char = String(UnicodeScalar(UInt8(0x61 + i % 26)))
                let start = CACurrentMediaTime()
                view.contentManager.applyEdit(replacing: caret ..< caret, with: char)
                view.layoutManager.textViewportLayoutController.layoutViewport()
                latencies.append((CACurrentMediaTime() - start) * 1000)
                caret = ByteOffset(caret.value + 1)
                try? await Task.sleep(for: .milliseconds(30))
            }
            results[name] = Stats(samples: latencies)
        }
        return results
    }

    // MARK: Reporting

    private func report(scroll: Stats?, dropped: Double, typing: [String: Stats]) {
        let refreshHz = Int((1.0 / refreshInterval).rounded())
        let rss = rssMB()
        var lines = [
            "RENDERSPIKE RESULTS corpus=\(corpusName) refresh=\(refreshHz)",
            "load_seconds=\(fmt(loadSeconds)) rss_mb=\(fmt(rss)) lines=\(view.contentManager.buffer.lineCount) bytes=\(view.contentManager.buffer.utf8Count)",
        ]
        var scrollPass = true, typePass = true
        if let scroll {
            scrollPass = scroll.p99 <= 17.0 && dropped < 1.0
            lines.append("scroll_p50_ms=\(fmt(scroll.p50)) scroll_p95_ms=\(fmt(scroll.p95)) scroll_p99_ms=\(fmt(scroll.p99)) scroll_max_ms=\(fmt(scroll.max)) dropped_pct=\(fmt(dropped))")
        }
        if !typing.isEmpty {
            typePass = typing.values.allSatisfy { $0.p99 < 16.0 }
            lines.append("type_start_p99_ms=\(fmt(typing["start"]?.p99 ?? -1)) type_middle_p99_ms=\(fmt(typing["middle"]?.p99 ?? -1)) type_end_p99_ms=\(fmt(typing["end"]?.p99 ?? -1))")
        }
        lines.append("VERDICT scroll=\(scroll == nil ? "n/a" : scrollPass ? "pass" : "fail") type=\(typing.isEmpty ? "n/a" : typePass ? "pass" : "fail")")
        print(lines.joined(separator: "\n"))
        let allPass = (scroll == nil || scrollPass) && (typing.isEmpty || typePass)
        exit(allPass ? 0 : 1)
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func rssMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
}

/// Percentile stats over millisecond samples.
struct Stats {
    let p50: Double, p95: Double, p99: Double, max: Double
    init(samples: [Double]) {
        let sorted = samples.sorted()
        func pct(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return -1 }
            let idx = Int(Double(sorted.count - 1) * p)
            return sorted[idx]
        }
        p50 = pct(0.50); p95 = pct(0.95); p99 = pct(0.99)
        max = sorted.last ?? -1
    }
}
