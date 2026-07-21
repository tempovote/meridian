import Foundation
import XCTest

/// Documents performance budget items that are explicitly deferred to later
/// roadmap milestones due to missing underlying architectural prerequisites.
final class DeferredBudgets: XCTestCase {
    /// Open 1 GB file (huge-file mode) < 1.5 s.
    ///
    /// Deferred to Milestone 7 (Scale + workspace).
    ///
    /// Per ROADMAP.md sequencing, mmap-backed rope leaves do not exist until M7.
    /// In M5, loading a 1 GB file reads the entire file into memory as a standard
    /// in-memory rope string buffer, exceeding the 64 MB huge-file threshold
    /// (`MeridianDocument.maxFileSize`). This budget will be implemented when
    /// mmap rope leaves land in M7.
    func testOpen1GBFileHugeFileModeBudgetDeferredToM7() throws {
        throw XCTSkip("Deferred to M7 per ROADMAP.md (mmap-backed rope leaves required for GB-scale huge-file mode)")
    }
}
