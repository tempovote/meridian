import AppKit
import DocumentCore

/// Benchmark CLI options. `scrollVelocityMultiplier` defaults to the
/// brief's 8×; Task 5's controller amendment exposes it as a tunable so a
/// crash at 8× can be bisected down without editing source (see
/// `BenchmarkDriver`'s doc comment and `main.swift`'s
/// `--scroll-velocity=<n>` flag).
struct BenchmarkPlan {
    var editOnly = false
    var scrollOnly = false
    var scrollVelocityMultiplier = 8.0
}

@MainActor
enum SpikeApp {
    static func run(corpusPath: String, benchmark: BenchmarkPlan?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        print("loading corpus \(corpusPath)…")
        let loadStart = Date()
        guard let data = FileManager.default.contents(atPath: corpusPath),
              let text = String(bytes: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read corpus as UTF-8\n".utf8))
            exit(2)
        }
        let buffer = TextBuffer(text)
        // Captured here — corpus read + rope build only — so window
        // creation below (unrelated to corpus load cost) never inflates
        // load_seconds in the benchmark report.
        let loadSeconds = Date().timeIntervalSince(loadStart)
        print("corpus loaded: \(buffer.utf8Count) bytes, \(buffer.lineCount) lines, in \(loadSeconds)s")

        let manager = RopeContentManager(buffer: buffer)
        let view = ViewportView(contentManager: manager)
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: view.estimatedDocumentHeight)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        scrollView.documentView = view
        scrollView.hasVerticalScroller = true

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false,
        )
        window.title = "RenderSpike — \((corpusPath as NSString).lastPathComponent)"
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        view.startDisplayLink()
        _ = window.makeFirstResponder(view)

        if let benchmark {
            let driver = BenchmarkDriver(
                view: view, scrollView: scrollView,
                corpusName: (corpusPath as NSString).lastPathComponent,
                loadSeconds: loadSeconds,
            )
            driver.editOnly = benchmark.editOnly
            driver.scrollOnly = benchmark.scrollOnly
            driver.scrollVelocityMultiplier = benchmark.scrollVelocityMultiplier
            driver.start()
        }

        app.run()
        exit(0)
    }
}
