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
/// Scroll-only: typing is not needed for this experiment (the brief only
/// asks whether Apple's own content manager survives sustained scrolling),
/// so there is no `keyDown`/`applyEdit` here.
@MainActor
final class ControlViewportView: NSView {
    let contentStorage: NSTextContentStorage
    let layoutManager = NSTextLayoutManager()
    let container: NSTextContainer
    let lineHeight: CGFloat
    let lineCount: Int
    var onFrame: ((CFTimeInterval, CFTimeInterval) -> Void)?

    private var fragments: [NSTextLayoutFragment] = []
    private var displayLink: CADisplayLink?

    /// - Parameters:
    ///   - text: whole corpus, loaded as a single `NSAttributedString` —
    ///     this is the thing under test (Apple's own content-storage path).
    ///   - lineCount: from the same rope the primary path uses, purely for
    ///     the `lineCount × lineHeight` document-height estimate (matches
    ///     `ViewportView.estimatedDocumentHeight`'s approach) — the rope
    ///     itself is not rendered here.
    init(text: String, lineCount: Int) {
        guard let font = RopeContentManager.attributes[.font] as? NSFont else {
            preconditionFailure("attributes must carry a font")
        }
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        self.lineCount = lineCount
        let attributed = NSAttributedString(string: text, attributes: RopeContentManager.attributes)
        contentStorage = NSTextContentStorage()
        contentStorage.attributedString = attributed
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

    var estimatedDocumentHeight: CGFloat {
        CGFloat(lineCount) * lineHeight + 20
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

/// Scroll-only benchmark driver for the control view. Reuses
/// `BenchmarkDriver.runSmoothScroll`'s logic verbatim (same pass count,
/// duration cap, velocity semantics, dropped-frame threshold) so the two
/// experiments are apples-to-apples; duplicated rather than shared because
/// `BenchmarkDriver` is typed to `ViewportView`/`RopeContentManager`
/// throughout and this is a temporary control, not a shape worth
/// generalizing the primary driver for.
@MainActor
final class ControlBenchmarkDriver {
    let view: ControlViewportView
    let scrollView: NSScrollView
    let corpusName: String
    let loadSeconds: Double
    var scrollVelocityMultiplier = 8.0

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
            print("# phase=scroll(control) start velocity=\(scrollVelocityMultiplier)")
            let (stats, dropped) = await runSmoothScroll()
            print("# phase=scroll(control) done")
            report(scroll: stats, dropped: dropped)
        }
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

    private func report(scroll: Stats, dropped: Double) {
        let refreshHz = Int((1.0 / refreshInterval).rounded())
        let scrollPass = scroll.p99 <= 17.0 && dropped < 1.0
        let lines = [
            "RENDERSPIKE CONTROL RESULTS corpus=\(corpusName) refresh=\(refreshHz)",
            "load_seconds=\(fmt(loadSeconds)) lines=\(view.lineCount)",
            "scroll_p50_ms=\(fmt(scroll.p50)) scroll_p95_ms=\(fmt(scroll.p95)) scroll_p99_ms=\(fmt(scroll.p99)) scroll_max_ms=\(fmt(scroll.max)) dropped_pct=\(fmt(dropped))",
            "VERDICT scroll=\(scrollPass ? "pass" : "fail")",
        ]
        print(lines.joined(separator: "\n"))
        exit(scrollPass ? 0 : 1)
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}

/// Entry point for `renderspike benchmark-control <corpus-path>` — builds
/// the control pipeline (see `ControlViewportView` doc comment) and runs
/// the scroll-only benchmark. Kept as a separate `enum` (mirroring
/// `SpikeApp`) rather than adding a branch inside `SpikeApp.run` so the
/// primary benchmark path is untouched by this experiment.
@MainActor
enum ControlSpikeApp {
    static func run(corpusPath: String, scrollVelocityMultiplier: Double) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        print("loading corpus \(corpusPath)… (CONTROL: NSTextContentStorage)")
        let loadStart = Date()
        guard let data = FileManager.default.contents(atPath: corpusPath),
              let text = String(bytes: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read corpus as UTF-8\n".utf8))
            exit(2)
        }
        // Built only for its lineCount (document-height estimate) — never
        // rendered in this experiment; the NSAttributedString above is the
        // thing actually under test.
        let buffer = TextBuffer(text)
        let loadSeconds = Date().timeIntervalSince(loadStart)
        print("corpus loaded: \(buffer.utf8Count) bytes, \(buffer.lineCount) lines, in \(loadSeconds)s")

        let view = ControlViewportView(text: text, lineCount: buffer.lineCount)
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: view.estimatedDocumentHeight)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        scrollView.documentView = view
        scrollView.hasVerticalScroller = true

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false,
        )
        window.title = "RenderSpike CONTROL — \((corpusPath as NSString).lastPathComponent)"
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        view.startDisplayLink()

        let driver = ControlBenchmarkDriver(
            view: view, scrollView: scrollView,
            corpusName: (corpusPath as NSString).lastPathComponent,
            loadSeconds: loadSeconds,
        )
        driver.scrollVelocityMultiplier = scrollVelocityMultiplier
        driver.start()

        app.run()
        exit(0)
    }
}
