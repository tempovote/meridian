import AppKit
import DocumentCore

#if DEBUG
    extension TextKit2Engine {
        /// Test hooks — compiled out of release builds.
        var storageStringForTesting: String {
            storage.string
        }

        /// Reads a single storage attribute at a UTF-16 offset — used by
        /// bracket-match tests to confirm a `.backgroundColor` attribute
        /// is (or isn't) present at a specific location, without needing
        /// to know the exact `NSColor` value.
        func storageAttributeForTesting(_ key: NSAttributedString.Key, at utf16Offset: Int) -> Any? {
            guard utf16Offset < storage.length else { return nil }
            return storage.attribute(key, at: utf16Offset, effectiveRange: nil)
        }

        var snapshotStringForTesting: String {
            buffer.string
        }

        var snapshotForTesting: TextBuffer {
            buffer
        }

        /// Simulates user typing by mutating the storage directly, exactly as
        /// NSTextView's insertText path does (delegate fires → user-edit path).
        func simulateUserTypingForTesting(replacing range: NSRange, with string: String) {
            storage.replaceCharacters(in: range, with: string)
        }

        var foldModelForTesting: FoldModel {
            foldModel
        }

        var hiddenUTF16SpansForTesting: [Range<Int>] {
            hiddenUTF16Spans
        }

        /// Awaits the in-flight highlight/fold parse kicked off by the last
        /// `load`/`apply`/user edit, so tests can assert on `foldModel`
        /// once the async `SyntaxService.parse` result has landed instead
        /// of sleeping.
        func waitForParseForTesting() async {
            await lastParseTask?.value
        }

        /// Awaits the in-flight deferred fold relayout (if any) scheduled
        /// by `refreshFoldLayoutDeferred()` from a real-typing edit, so
        /// tests can assert on the post-relayout TextKit 2 layout state
        /// deterministically instead of sleeping.
        func waitForDeferredFoldRelayoutForTesting() async {
            await deferredFoldRelayoutTask?.value
        }
    }
#endif
