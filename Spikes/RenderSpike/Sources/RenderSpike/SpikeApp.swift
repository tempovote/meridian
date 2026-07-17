import AppKit
import DocumentCore

/// Task 5 fills this with the benchmark phases; empty until then.
struct BenchmarkPlan {}

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
        print("corpus loaded: \(buffer.utf8Count) bytes, \(buffer.lineCount) lines, in \(Date().timeIntervalSince(loadStart))s")

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

        // benchmark wiring arrives in Task 5; interactive mode just runs.
        app.run()
        exit(0)
    }
}
