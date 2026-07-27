/// Which editor features a file's size and line shape permit.
///
/// Meridian opens gigabyte files by switching off everything that needs a
/// whole-file scan, rather than by refusing to open them. This type is the
/// single place that decision is made, so the rule is testable without
/// launching the app and cannot drift between the editor, the gutter and
/// the minimap.
public struct HugeFileProfile: Sendable, Equatable {
    /// Files at or above this size enter huge mode.
    public static let hugeThresholdBytes = 64 * 1024 * 1024
    /// A single line at or above this length forbids soft wrap at any file
    /// size: wrapping one enormous paragraph is what produced ADR 0009's
    /// 11 GB layout blow-up on a 100 MB single-line file.
    public static let pathologicalLineBytes = 1024 * 1024

    /// The restriction tier a profile falls into, derived from ``HugeFileProfile/byteSize``
    /// and ``HugeFileProfile/longestLineUTF8Length``. Coarser than ``Capabilities`` — it
    /// exists for banners and logging that want a single label rather than per-feature detail.
    public enum Level: Sendable, Equatable {
        /// Everything on.
        case normal
        /// File is at or above ``hugeThresholdBytes``.
        case huge
        /// File is below the size threshold but contains a line at or above
        /// ``pathologicalLineBytes``.
        case pathologicalLines
    }

    /// One flag per feature that has a whole-file or whole-line cost.
    public struct Capabilities: Sendable, Equatable {
        /// Tree-sitter highlighting walks the whole syntax tree to assign
        /// tokens; off above the huge threshold because that walk doesn't
        /// stay bounded as file size grows.
        public let syntaxHighlighting: Bool
        /// Fold-range discovery scans the full syntax tree to find
        /// foldable regions; off above the huge threshold for the same
        /// reason as ``syntaxHighlighting``.
        public let folding: Bool
        /// The minimap renders a scaled thumbnail of every line in the
        /// file, so its cost scales with total line count; off above the
        /// huge threshold.
        public let minimap: Bool
        /// The git gutter diffs the whole file against its VCS blob to
        /// know which lines changed; off above the huge threshold.
        public let gitGutter: Bool
        /// Bracket matching over huge files falls back to scanning
        /// outward from the cursor with no upper bound, so it's disabled
        /// above the huge threshold rather than risk an unbounded scan.
        public let bracketMatching: Bool
        /// Soft wrap must lay out every character of a line to know where
        /// it breaks, so it is disabled above the huge threshold and also
        /// for any single line at or above ``pathologicalLineBytes`` —
        /// see that constant's doc comment for the incident that motivated it.
        public let softWrap: Bool
        /// Search streams over rope chunks and never materializes the
        /// document, so it survives huge mode.
        public let findInFiles: Bool
    }

    /// The restriction tier this profile falls into. A coarse summary of
    /// ``capabilities`` for banners and logging; feature code should read
    /// ``capabilities`` directly rather than switch on this.
    public let level: Level
    /// The per-feature availability this profile grants, computed as the
    /// union of the size-threshold and line-length restrictions.
    public let capabilities: Capabilities
    /// The file's size on disk, in bytes, as supplied to ``init(byteSize:longestLineUTF8Length:)``.
    public let byteSize: Int
    /// The longest line's length in UTF-8 bytes, as supplied to ``init(byteSize:longestLineUTF8Length:)``.
    public let longestLineUTF8Length: Int

    /// Derives a profile purely from the two supplied measurements: `byteSize` (the
    /// file's total size on disk, in bytes) and `longestLineUTF8Length` (the length in
    /// UTF-8 bytes of that file's longest line). No I/O happens here — callers are
    /// expected to have already measured the file.
    public init(byteSize: Int, longestLineUTF8Length: Int) {
        self.byteSize = byteSize
        self.longestLineUTF8Length = longestLineUTF8Length

        let isHuge = byteSize >= Self.hugeThresholdBytes
        let hasPathologicalLine = longestLineUTF8Length >= Self.pathologicalLineBytes

        level = if isHuge {
            .huge
        } else if hasPathologicalLine {
            .pathologicalLines
        } else {
            .normal
        }

        // Union of restrictions: a huge file with a pathological line is
        // restricted by both rules, never relaxed by the weaker one.
        capabilities = Capabilities(
            syntaxHighlighting: !isHuge,
            folding: !isHuge,
            minimap: !isHuge,
            gitGutter: !isHuge,
            bracketMatching: !isHuge,
            softWrap: !isHuge && !hasPathologicalLine,
            findInFiles: true,
        )
    }

    /// A profile with every capability enabled — for untitled documents and
    /// tests that predate a real file on disk.
    public static let unrestricted = HugeFileProfile(byteSize: 0, longestLineUTF8Length: 0)

    /// Display names of the features this profile switches off, for the
    /// banner. Ordered for stable presentation, not alphabetically.
    public var disabledFeatureNames: [String] {
        var names: [String] = []
        if !capabilities.syntaxHighlighting {
            names.append("Syntax highlighting")
        }
        if !capabilities.folding {
            names.append("Code folding")
        }
        if !capabilities.minimap {
            names.append("Minimap")
        }
        if !capabilities.gitGutter {
            names.append("Git gutter")
        }
        if !capabilities.bracketMatching {
            names.append("Bracket matching")
        }
        if !capabilities.softWrap {
            names.append("Soft wrap")
        }
        return names
    }
}
