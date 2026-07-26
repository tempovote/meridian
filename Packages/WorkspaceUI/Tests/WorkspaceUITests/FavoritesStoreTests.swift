import Foundation
import Testing
@testable import WorkspaceUI

// FavoritesStore uses security-scoped bookmarks only when building bookmark Data
// from real, sandbox-accessible URLs. In tests we use /tmp URLs which are
// always accessible, so the save path gracefully skips bookmark creation without
// crashing. All public API (add/remove/toggle/isFavorite) is exercised in memory.

// MARK: - Tests

@Suite("FavoritesStore")
@MainActor
struct FavoritesStoreTests {
    private func makeStore() -> FavoritesStore {
        FavoritesStore()
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name).txt")
    }

    @Test("starts empty")
    func startsEmpty() {
        let store = makeStore()
        #expect(store.favorites.isEmpty)
    }

    @Test("add inserts URL")
    func addInserts() {
        let store = makeStore()
        let fileURL = url("a")
        store.add(fileURL)
        #expect(store.favorites.count == 1)
        #expect(store.isFavorite(fileURL))
    }

    @Test("add is idempotent")
    func addIdempotent() {
        let store = makeStore()
        let fileURL = url("b")
        store.add(fileURL)
        store.add(fileURL)
        #expect(store.favorites.count == 1)
    }

    @Test("remove deletes URL")
    func removeDeletes() {
        let store = makeStore()
        let fileURL = url("c")
        store.add(fileURL)
        store.remove(fileURL)
        #expect(store.favorites.isEmpty)
        #expect(!store.isFavorite(fileURL))
    }

    @Test("remove is a no-op for absent URL")
    func removeAbsent() {
        let store = makeStore()
        store.remove(url("ghost"))
        #expect(store.favorites.isEmpty)
    }

    @Test("toggle adds when absent")
    func toggleAdds() {
        let store = makeStore()
        let fileURL = url("d")
        let result = store.toggle(fileURL)
        #expect(result == true)
        #expect(store.isFavorite(fileURL))
    }

    @Test("toggle removes when present")
    func toggleRemoves() {
        let store = makeStore()
        let fileURL = url("e")
        store.add(fileURL)
        let result = store.toggle(fileURL)
        #expect(result == false)
        #expect(!store.isFavorite(fileURL))
    }

    @Test("insertion order is preserved")
    func insertionOrder() {
        let store = makeStore()
        let urls = (1 ... 5).map { url("file\($0)") }
        urls.forEach { store.add($0) }
        #expect(store.favorites == urls)
    }

    @Test("multiple URLs can coexist")
    func multipleURLs() {
        let store = makeStore()
        let urlA = url("multi_a")
        let urlB = url("multi_b")
        store.add(urlA)
        store.add(urlB)
        #expect(store.isFavorite(urlA))
        #expect(store.isFavorite(urlB))
        #expect(store.favorites.count == 2)
    }

    @Test("remove only affects the targeted URL")
    func removeSelectivelyTargets() {
        let store = makeStore()
        let keepURL = url("keep")
        let dropURL = url("drop")
        store.add(keepURL)
        store.add(dropURL)
        store.remove(dropURL)
        #expect(store.isFavorite(keepURL))
        #expect(!store.isFavorite(dropURL))
        #expect(store.favorites.count == 1)
    }
}
