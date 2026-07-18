import AppKit
import DocumentCore

/// EXPERIMENT 1 (control group, see task-5-report.md "## Differentiation
/// experiments"): does TextKit 2 itself crash under sustained scrolling, or
/// is Task 5's `NSCountableTextLocation.compare:` crash specific to
/// `RopeContentManager`'s custom `NSTextLocation`? This mirrors
/// `ViewportView`'s viewport-layout wiring exactly, but swaps
/// `RopeContentManager` for Apple's own `NSTextContentStorage`
/// (`NSAttributedString`-backed) — the whole document loaded as one
/// attributed string, with the same monospace attributes.
///
/// Deliberately duplicated rather than generalizing `ViewportView` to be
/// content-manager-agnostic: this is a throwaway control, not a shape the
/// real editor will use, and duplication keeps the primary
/// (`RopeContentManager`) path completely untouched by this investigation.
///
/// DEVIATION (evidence-gap follow-up, binding brief): the original
/// scroll-only doc comment above ("typing is not needed for this
/// experiment") no longer holds — edit/typing latency on
/// `NSTextContentStorage` was never measured and is a named evidence gap
/// blocking the ADR 0009 hybrid verdict. `typingPositions` and `caretIndex`
/// below exist to support both the benchmark driver's typing phase and the
/// `view-control` interactive mode's basic typing.
@MainActor
final class ControlViewportView: NSView {
    let contentStorage: NSTextContentStorage
    let layoutManager = NSTextLayoutManager()
    let container: NSTextContainer
    let lineHeight: CGFloat
    let lineCount: Int
    /// UTF-16 character indices for the three typing-benchmark positions
    /// (start/middle/end), computed once at load time from the same rope
    /// the primary path uses — mirrors `BenchmarkDriver.runTyping`'s byte
    /// positions, converted to UTF-16 (NSTextStorage/NSRange's native
    /// unit) via `TextBuffer.utf16Offset(of:)`.
    let typingPositions: [(String, Int)]
    /// Caret for `view-control`'s interactive typing, in UTF-16 character
    /// indices into `contentStorage.textStorage`. Starts at document start.
    /// DEVIATION (brief, "click-to-move-caret optional — if non-trivial,
    /// skip it"): no click-to-move and no on-screen caret indicator are
    /// implemented — computing the caret's visual line from a UTF-16
    /// character index would require scanning the string (unbounded cost
    /// at 1 GB), unlike the primary path's O(1) `buffer.linePosition(of:)`.
    /// The feel-check only needs scrolling + some responsive typing at a
    /// fixed position, per the brief; typing always happens at whatever
    /// `caretIndex` currently is (document start, then wherever prior
    /// keystrokes left it).
    var caretIndex = 0
    var onFrame: ((CFTimeInterval, CFTimeInterval) -> Void)?

    private var fragments: [NSTextLayoutFragment] = []
    private var displayLink: CADisplayLink?

    /// - Parameters:
    ///   - text: whole corpus, loaded as a single `NSAttributedString` —
    ///     this is the thing under test (Apple's own content-storage path).
    ///   - buffer: the same rope snapshot the primary path builds, used
    ///     only for its `lineCount` (document-height estimate, matching
    ///     `ViewportView.estimatedDocumentHeight`) and to compute
    ///     `typingPositions` via the same byte→UTF-16 conversion the
    ///     primary path's `RopeContentManager` uses — the rope itself is
    ///     never rendered here.
    init(text: String, buffer: TextBuffer) {
        guard let font = RopeContentManager.attributes[.font] as? NSFont else {
            preconditionFailure("attributes must carry a font")
        }
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        lineCount = buffer.lineCount
        typingPositions = Self.computeTypingPositions(buffer: buffer)
        let attributed = NSAttributedString(string: text, attributes: RopeContentManager.attributes)
        contentStorage = NSTextContentStorage()
        // DEVIATION / IDIOM FINDING (evidence-gap follow-up): assigning
        // `contentStorage.attributedString = attributed` (the shape this
        // file originally used, when only scrolling was under test) loads
        // the content but leaves `contentStorage.textStorage` `nil` —
        // confirmed empirically (a standalone probe: `.textStorage` reads
        // back `nil` immediately after setting `.attributedString`). Since
        // typing here edits through `.textStorage`, that path must instead
        // go through the lazily-created `NSTextStorage` `.textStorage`
        // vends and load content into *that* — after which
        // `.attributedString` stays in sync automatically (verified: it
        // reflects storage edits made this way). Assigning `.attributedString`
        // directly is a write-only convenience for content that will never
        // be edited; anything meaning to mutate via `NSTextStorage` later
        // must seed content through `.textStorage` from the start.
        guard let initialStorage = contentStorage.textStorage else {
            preconditionFailure("NSTextContentStorage did not lazily create its textStorage")
        }
        contentStorage.performEditingTransaction {
            initialStorage.setAttributedString(attributed)
        }
        container = NSTextContainer(size: CGSize(width: 1200, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 5
        super.init(frame: .zero)
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
        layoutManager.textViewportLayoutController.delegate = self
        wantsLayer = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var estimatedDocumentHeight: CGFloat {
        CGFloat(lineCount) * lineHeight + 20
    }

    /// Same three positions as `BenchmarkDriver.runTyping` (line 10,
    /// lineCount/2, lineCount−10), converted from byte offsets to UTF-16
    /// character indices — the unit `NSTextStorage`/`NSRange` use — via
    /// `TextBuffer.utf16Offset(of:)`, the same conversion
    /// `RopeContentManager` performs internally for the primary path.
    static func computeTypingPositions(buffer: TextBuffer) -> [(String, Int)] {
        let byteOffsets: [(String, ByteOffset)] = [
            ("start", buffer.byteRange(ofLine: min(10, buffer.lineCount - 1)).lowerBound),
            ("middle", buffer.byteRange(ofLine: buffer.lineCount / 2).lowerBound),
            ("end", buffer.byteRange(ofLine: max(buffer.lineCount - 10, 0)).lowerBound),
        ]
        return byteOffsets.map { name, byte in (name, buffer.utf16Offset(of: byte).value) }
    }

    func startDisplayLink() {
        let link = displayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        onFrame?(link.timestamp, link.targetTimestamp)
        layoutManager.textViewportLayoutController.layoutViewport()
    }

    // MARK: Input (view-control interactive mode)

    /// Basic typing at `caretIndex`: printable characters, return (→ "\n"),
    /// and delete (backspace one UTF-16 unit back). Mirrors
    /// `ViewportView.keyDown`'s character filter exactly; the edit idiom
    /// is the one established in `ControlBenchmarkDriver.runTyping` below
    /// (`performEditingTransaction` + `NSTextStorage.replaceCharacters`).
    override func keyDown(with event: NSEvent) {
        guard let textStorage = contentStorage.textStorage else {
            assertionFailure("NSTextContentStorage has no textStorage")
            return
        }
        if event.keyCode == 51 { // delete
            guard caretIndex > 0 else { return }
            contentStorage.performEditingTransaction {
                textStorage.replaceCharacters(in: NSRange(location: caretIndex - 1, length: 1), with: "")
            }
            caretIndex -= 1
        } else if let chars = event.characters, !chars.isEmpty,
                  chars.allSatisfy({ !$0.isASCII || $0.asciiValue.map { $0 >= 0x20 } == true || $0 == "\r" }) {
            let insert = chars == "\r" ? "\n" : chars
            contentStorage.performEditingTransaction {
                textStorage.replaceCharacters(in: NSRange(location: caretIndex, length: 0), with: insert)
            }
            caretIndex += (insert as NSString).length
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        for fragment in fragments {
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: context)
        }
    }
}

// Same nonisolated/assumeIsolated bridging pattern as
// ViewportView+NSTextViewportLayoutControllerDelegate — see that type's doc
// comment for why this is sound (NSTextViewportLayoutController invokes its
// delegate synchronously on the thread that owns the layout manager).
extension ControlViewportView: NSTextViewportLayoutControllerDelegate {
    nonisolated func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        let unsafeSelf = self
        return MainActor.assumeIsolated {
            let visible = unsafeSelf.enclosingScrollView?.documentVisibleRect ?? unsafeSelf.bounds
            return visible.insetBy(dx: 0, dy: -visible.height)
        }
    }

    nonisolated func textViewportLayoutControllerWillLayout(_ controller: NSTextViewportLayoutController) {
        let unsafeSelf = self
        MainActor.assumeIsolated {
            unsafeSelf.fragments.removeAll(keepingCapacity: true)
        }
    }

    nonisolated func textViewportLayoutController(
        _ controller: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment,
    ) {
        let unsafeSelf = self
        nonisolated(unsafe) let unsafeFragment = textLayoutFragment
        MainActor.assumeIsolated {
            unsafeSelf.fragments.append(unsafeFragment)
        }
    }

    nonisolated func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        let unsafeSelf = self
        MainActor.assumeIsolated {
            unsafeSelf.needsDisplay = true
        }
    }
}

/// Benchmark driver for the control view. Reuses
/// `BenchmarkDriver.runSmoothScroll`'s logic verbatim (same pass count,
/// duration cap, velocity semantics, dropped-frame threshold) so the two
/// experiments are apples-to-apples; duplicated rather than shared because
/// `BenchmarkDriver` is typed to `ViewportView`/`RopeContentManager`
/// throughout and this is a temporary control, not a shape worth
/// generalizing the primary driver for.
///
/// DEVIATION (evidence-gap follow-up, binding brief): this was originally
/// scroll-only (see the type's old doc comment, now superseded). It now
/// also runs a typing phase mirroring `BenchmarkDriver.runTyping` exactly
/// (same 40 keystrokes × 3 positions × 30 ms cadence, same latency
/// definition, same viewport-parked-at-top setup, same phase ordering —
/// typing before scroll — for the same reason: both phases in one
/// invocation should measure typing with the viewport at the document
/// top). `--scroll-only` preserves the exact old behavior (scroll phase
/// only) for direct comparability with prior scroll-only runs recorded in
/// task-5-report.md. `--edit-only` is a symmetric addition (not requested
/// by the brief, but present on the primary driver and useful for
/// isolating typing latency without paying a 3×20s scroll cost per corpus
/// size) — default with neither flag runs both phases, matching the
/// primary driver's default.
@MainActor
final class ControlBenchmarkDriver {
    let view: ControlViewportView
    let scrollView: NSScrollView
    let corpusName: String
    let loadSeconds: Double
    var scrollVelocityMultiplier = 8.0
    var editOnly = false
    var scrollOnly = false

    private var frameDeltas: [Double] = []
    private var lastTimestamp: CFTimeInterval?
    private var refreshInterval: Double = 1.0 / 60.0

    init(view: ControlViewportView, scrollView: NSScrollView, corpusName: String, loadSeconds: Double) {
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
            if !scrollOnly {
                print("# phase=typing(control) start")
                typeStats = await runTyping()
                print("# phase=typing(control) done")
            }
            if !editOnly {
                print("# phase=scroll(control) start velocity=\(scrollVelocityMultiplier)")
                (scrollStats, droppedPct) = await runSmoothScroll()
                print("# phase=scroll(control) done")
            }
            report(scroll: scrollStats, dropped: droppedPct, typing: typeStats)
        }
    }

    // MARK: Phases

    /// Mirrors `BenchmarkDriver.runTyping` exactly: 40 keystrokes at each
    /// of three positions (start/middle/end), latency = synchronous edit +
    /// immediate `layoutViewport()`, viewport left parked at document top
    /// throughout (no scroll/jump between positions).
    ///
    /// Edit idiom: `NSTextContentStorage.textStorage` is the
    /// `NSTextStorage` backing the content storage (auto-created when
    /// `attributedString` is set, per Apple's documented behavior);
    /// mutating it inside `performEditingTransaction` is the correct way
    /// to edit content that keeps `NSTextContentStorage`'s internal
    /// bookkeeping and the attached `NSTextLayoutManager`'s invalidation
    /// in sync — bypassing the transaction (mutating `textStorage`
    /// directly) is undocumented and not used here.
    private func runTyping() async -> [String: Stats] {
        var results: [String: Stats] = [:]
        guard let textStorage = view.contentStorage.textStorage else {
            preconditionFailure("NSTextContentStorage has no textStorage")
        }
        for (name, charIndex) in view.typingPositions {
            var latencies: [Double] = []
            var caret = charIndex
            for i in 0 ..< 40 {
                let char = String(UnicodeScalar(UInt8(0x61 + i % 26)))
                let start = CACurrentMediaTime()
                view.contentStorage.performEditingTransaction {
                    textStorage.replaceCharacters(in: NSRange(location: caret, length: 0), with: char)
                }
                view.layoutManager.textViewportLayoutController.layoutViewport()
                latencies.append((CACurrentMediaTime() - start) * 1000)
                caret += 1
                try? await Task.sleep(for: .milliseconds(30))
            }
            results[name] = Stats(samples: latencies)
        }
        return results
    }

    /// Identical shape to `BenchmarkDriver.runSmoothScroll`: 3 passes
    /// top→bottom→top at `scrollVelocityMultiplier` viewport-heights/second,
    /// capped at 20 s per pass, plain `NSScrollView` bounds scrolling only
    /// (no `jump`/`relocateViewport` call, mirroring the primary driver's
    /// "safe, continuous small-delta" regime).
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

    private func report(scroll: Stats?, dropped: Double, typing: [String: Stats]) {
        let refreshHz = Int((1.0 / refreshInterval).rounded())
        var lines = [
            "RENDERSPIKE CONTROL RESULTS corpus=\(corpusName) refresh=\(refreshHz)",
            "load_seconds=\(fmt(loadSeconds)) lines=\(view.lineCount)",
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
}

/// Entry point for `renderspike benchmark-control <corpus-path>` — builds
/// the control pipeline (see `ControlViewportView` doc comment) and runs
/// the benchmark (typing + scroll by default). Kept as a separate `enum`
/// (mirroring `SpikeApp`) rather than adding a branch inside `SpikeApp.run`
/// so the primary benchmark path is untouched by this experiment.
@MainActor
enum ControlSpikeApp {
    /// Shared corpus-load + window/pipeline setup for both
    /// `benchmark-control` and `view-control`. Returns the assembled view,
    /// scroll view, and load metadata; callers decide whether to attach a
    /// `ControlBenchmarkDriver` or just run the app interactively.
    private static func buildPipeline(corpusPath: String) -> (
        view: ControlViewportView, scrollView: NSScrollView, window: NSWindow, loadSeconds: Double
    ) {
        print("loading corpus \(corpusPath)… (CONTROL: NSTextContentStorage)")
        let loadStart = Date()
        guard let data = FileManager.default.contents(atPath: corpusPath),
              let text = String(bytes: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read corpus as UTF-8\n".utf8))
            exit(2)
        }
        // Built for its lineCount (document-height estimate) and
        // typingPositions (byte→UTF-16 conversion) — never rendered in
        // this experiment; the NSAttributedString the view builds
        // internally is the thing actually under test.
        let buffer = TextBuffer(text)
        let loadSeconds = Date().timeIntervalSince(loadStart)
        print("corpus loaded: \(buffer.utf8Count) bytes, \(buffer.lineCount) lines, in \(loadSeconds)s")

        let view = ControlViewportView(text: text, buffer: buffer)
        print("typing positions (utf16 char indices): \(view.typingPositions.map { "\($0.0)=\($0.1)" }.joined(separator: " "))")
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: view.estimatedDocumentHeight)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        scrollView.documentView = view
        scrollView.hasVerticalScroller = true

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false,
        )
        window.contentView = scrollView
        return (view, scrollView, window, loadSeconds)
    }

    static func run(corpusPath: String, scrollVelocityMultiplier: Double, editOnly: Bool, scrollOnly: Bool) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let (view, scrollView, window, loadSeconds) = buildPipeline(corpusPath: corpusPath)
        window.title = "RenderSpike CONTROL — \((corpusPath as NSString).lastPathComponent)"
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        view.startDisplayLink()

        let driver = ControlBenchmarkDriver(
            view: view, scrollView: scrollView,
            corpusName: (corpusPath as NSString).lastPathComponent,
            loadSeconds: loadSeconds,
        )
        driver.scrollVelocityMultiplier = scrollVelocityMultiplier
        driver.editOnly = editOnly
        driver.scrollOnly = scrollOnly
        driver.start()

        app.run()
        exit(0)
    }

    /// Entry point for `renderspike view-control <corpus-path>` — the
    /// interactive counterpart to `benchmark-control`, for the mandatory
    /// manual feel-check on the `NSTextContentStorage` path (the primary
    /// path's `view` mode crashes when scrolled, so it cannot be used for
    /// this). No benchmark driver is attached: the display link keeps
    /// `layoutViewport()` running every frame (so both scrolling and
    /// typing feed back into layout immediately), and `ControlViewportView`
    /// handles typing directly via `keyDown` at a caret that starts at
    /// document start.
    static func runInteractive(corpusPath: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let (view, _, window, _) = buildPipeline(corpusPath: corpusPath)
        window.title = "RenderSpike CONTROL (interactive) — \((corpusPath as NSString).lastPathComponent)"
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        view.startDisplayLink()
        _ = window.makeFirstResponder(view)

        app.run()
        exit(0)
    }
}
