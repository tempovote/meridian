import Darwin
import Foundation

enum AppProcessRunner {
    /// Locates the compiled `Meridian` application executable.
    static var appExecutableURL: URL? {
        let bundleURL = Bundle.main.bundleURL
        // When running under `xcodebuild test`, Bundle.main points inside
        // BuiltProductsDir/MeridianPerformanceTests.xctest
        let possibleLocations = [
            bundleURL.deletingLastPathComponent().appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
            bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("Meridian.app/Contents/MacOS/Meridian"),
        ]
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
