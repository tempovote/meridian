import Foundation

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
        public let syntaxHighlighting: Bool
        public let folding: Bool
        public let minimap: Bool
        public let gitGutter: Bool
        public let bracketMatching: Bool
        public let softWrap: Bool
        /// Search streams over rope chunks and never materializes the
        /// document, so it survives huge mode.
        public let findInFiles: Bool
    }

    public let level: Level
    public let capabilities: Capabilities
    public let byteSize: Int
    public let longestLineUTF8Length: Int

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
