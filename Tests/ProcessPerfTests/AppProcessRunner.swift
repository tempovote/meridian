import Darwin
import Foundation

enum AppProcessRunner {
    /// Locates the compiled `Meridian` application executable.
    static var appExecutableURL: URL? {
        let env = ProcessInfo.processInfo.environment
        var possibleLocations: [URL] = []

        // When this bundle runs un-hosted (no TEST_HOST — see
        // MeridianProcessPerfTests in project.yml), the process is
        // `xctest` itself, loaded from inside Xcode's own toolchain
        // directory, so `Bundle.main` is useless: it points at Xcode, not
        // at BuiltProductsDir. `xcodebuild test` does, however, always set
        // these two environment variables to locate the un-hosted bundle,
        // so prefer them.
        if let xctestBundlePath = env["XCTestBundlePath"] {
            possibleLocations.append(
                URL(fileURLWithPath: xctestBundlePath).deletingLastPathComponent()
                    .appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
            )
        }
        if let builtProductsDir = env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"]?.split(separator: ":").first {
            possibleLocations.append(
                URL(fileURLWithPath: String(builtProductsDir))
                    .appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
            )
        }

        // Fallback heuristics for a hosted test bundle, where Bundle.main
        // does point inside BuiltProductsDir/<Something>.xctest.
        let bundleURL = Bundle.main.bundleURL
        possibleLocations.append(contentsOf: [
            bundleURL.deletingLastPathComponent().appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
            bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
        ])

        for url in possibleLocations {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Measures cold launch time from process start to first window stdout signal.
    static func measureColdLaunch() throws -> Duration? {
        guard let exeURL = appExecutableURL else {
            return nil
        }

        let process = Process()
        process.executableURL = exeURL
        process.arguments = ["--perf-cold-launch"]
        let pipe = Pipe()
        process.standardOutput = pipe

        let clock = ContinuousClock()
        let start = clock.now
        try process.run()

        let reader = pipe.fileHandleForReading
        let data = reader.readDataToEndOfFile()
        let elapsed = start.duration(to: clock.now)
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        if output.contains("[MERIDIAN_PERF] FIRST_WINDOW_READY") {
            return elapsed
        }
        return nil
    }

    /// Measures resident memory (RSS in MB) when running with specified tab count.
    static func measureIdleMemoryMB(tabCount: Int = 10) throws -> Double? {
        guard let exeURL = appExecutableURL else {
            return nil
        }

        let process = Process()
        process.executableURL = exeURL
        process.arguments = ["--perf-idle-tabs", "\(tabCount)"]
        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let reader = pipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(10)
        var lineBuffer = ""

        while Date() < deadline, process.isRunning {
            let data = reader.availableData
            if data.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            if let str = String(data: data, encoding: .utf8) {
                lineBuffer += str
                if lineBuffer.contains("[MERIDIAN_PERF] IDLE_TABS_READY") {
                    break
                }
            }
        }

        guard lineBuffer.contains("[MERIDIAN_PERF] IDLE_TABS_READY") else {
            return nil
        }

        // Settling time to measure idle memory
        Thread.sleep(forTimeInterval: 0.2)

        if let rssBytes = getProcessResidentMemoryBytes(pid: process.processIdentifier) {
            return Double(rssBytes) / (1024.0 * 1024.0)
        }
        return nil
    }

    /// One file-open measurement through the real app process.
    struct FileOpenMeasurement {
        let timeToVisible: Duration
        let peakRSSBytes: UInt64
        let openFailed: Bool
        /// True when the app never reported the file visible before the
        /// deadline. A legitimate baseline result, not a harness error —
        /// which is exactly why it is a field rather than a nil return.
        let timedOut: Bool
    }

    /// Launches the app with `--perf-open`, samples RSS every 50 ms while
    /// the open proceeds, and returns the peak. Sampling (rather than a
    /// single reading at the end) is required: the transient copies this
    /// milestone exists to remove are freed before the open completes, so
    /// an end-state reading would under-report the true peak.
    static func measureFileOpen(path: String, timeout: TimeInterval = 300) throws -> FileOpenMeasurement? {
        guard let exeURL = appExecutableURL else { return nil }

        let process = Process()
        process.executableURL = exeURL
        process.arguments = ["--perf-open", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let reader = pipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(timeout)
        var lineBuffer = ""
        var peakRSS: UInt64 = 0

        while Date() < deadline, process.isRunning {
            if let rss = getProcessResidentMemoryBytes(pid: process.processIdentifier) {
                peakRSS = max(peakRSS, rss)
            }
            let data = reader.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                lineBuffer += str
            }
            if lineBuffer.contains("[MERIDIAN_PERF] FILE_VISIBLE")
                || lineBuffer.contains("[MERIDIAN_PERF] FILE_OPEN_FAILED")
            {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if lineBuffer.contains("[MERIDIAN_PERF] FILE_OPEN_FAILED") {
            return FileOpenMeasurement(timeToVisible: .zero, peakRSSBytes: peakRSS, openFailed: true, timedOut: false)
        }
        guard let markerRange = lineBuffer.range(of: "[MERIDIAN_PERF] FILE_VISIBLE ") else {
            // No marker before the deadline: the app is still working. Report
            // it as a timed-out measurement so the caller can record it.
            return FileOpenMeasurement(
                timeToVisible: .seconds(Int(timeout)),
                peakRSSBytes: peakRSS,
                openFailed: false,
                timedOut: true,
            )
        }
        let tail = lineBuffer[markerRange.upperBound...]
        let msText = tail.prefix { !$0.isNewline }
        guard let ms = Double(msText) else { return nil }

        return FileOpenMeasurement(
            timeToVisible: .milliseconds(Int(ms.rounded())),
            peakRSSBytes: peakRSS,
            openFailed: false,
            timedOut: false,
        )
    }

    private static func getProcessResidentMemoryBytes(pid: pid_t) -> UInt64? {
        var procInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &procInfo, Int32(size))
        if result == size {
            return procInfo.pti_resident_size
        }
        return nil
    }
}
