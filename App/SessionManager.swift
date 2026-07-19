import AppKit
import Foundation

/// Recorded session state for a single document.
public struct DocumentSessionState: Codable, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

/// Recorded application session state across restarts.
public struct ApplicationSessionState: Codable, Sendable {
    public let openDocuments: [DocumentSessionState]

    public init(openDocuments: [DocumentSessionState]) {
        self.openDocuments = openDocuments
    }
}

/// Manages application session saving & restoration.
@MainActor
public enum SessionManager {
    private static var sessionFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Meridian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    /// Saves current session state for all open documents.
    public static func saveSession(documents: [MeridianDocument]) {
        let states = documents.compactMap { doc -> DocumentSessionState? in
            guard let url = doc.fileURL else { return nil }
            return DocumentSessionState(fileURL: url)
        }
        let session = ApplicationSessionState(openDocuments: states)
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: sessionFileURL, options: .atomic)
        }
    }

    /// Restores session by returning previously opened document URLs.
    public static func restoreSession() -> [URL] {
        guard let data = try? Data(contentsOf: sessionFileURL),
              let session = try? JSONDecoder().decode(ApplicationSessionState.self, from: data)
        else {
            return []
        }
        return session.openDocuments.map(\.fileURL)
    }
}
