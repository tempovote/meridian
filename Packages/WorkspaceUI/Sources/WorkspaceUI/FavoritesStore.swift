import Foundation

/// Persists the user's set of favourite file URLs across app launches.
///
/// Stored at `~/Library/Application Support/Meridian/favorites.json`.
/// Thread-safe: all mutations must occur on `@MainActor` callers
/// (this object is `@MainActor`-isolated via `ObservableObject`).
@MainActor
public final class FavoritesStore: ObservableObject {
    /// The ordered list of favourite URLs (order = insertion order).
    @Published public private(set) var favorites: [URL] = []

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask,
        ).first!
        let dir = appSupport.appendingPathComponent("Meridian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("favorites.json")
    }

    public init() {
        load()
    }

    // MARK: - Public API

    /// Whether `url` is currently a favourite.
    public func isFavorite(_ url: URL) -> Bool {
        favorites.contains(url)
    }

    /// Adds `url` to favourites (no-op if already present).
    public func add(_ url: URL) {
        guard !favorites.contains(url) else { return }
        favorites.append(url)
        save()
    }

    /// Removes `url` from favourites (no-op if absent).
    public func remove(_ url: URL) {
        favorites.removeAll { $0 == url }
        save()
    }

    /// Toggles favourite state; returns the new `isFavorite` value.
    @discardableResult
    public func toggle(_ url: URL) -> Bool {
        if isFavorite(url) {
            remove(url)
            return false
        } else {
            add(url)
            return true
        }
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data = try? Data(contentsOf: Self.fileURL),
            let bookmarks = try? JSONDecoder().decode([Data].self, from: data)
        else { return }

        favorites = bookmarks.compactMap { bookmarkData -> URL? in
            var isStale = false
            return try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale,
            )
        }
    }

    private func save() {
        let bookmarks = favorites.compactMap { url -> Data? in
            try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
        }
        if let data = try? JSONEncoder().encode(bookmarks) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
