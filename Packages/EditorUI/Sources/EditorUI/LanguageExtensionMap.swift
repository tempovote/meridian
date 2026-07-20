/// Maps a file extension to its `SyntaxKit` `languageID`, driving syntax
/// highlighting grammar selection. Extend this table (not a `switch`) when
/// a new grammar is bundled in `SyntaxKit`.
private let fileExtensionToLanguageID: [String: String] = [
    "json": "json",
    "swift": "swift",
    "js": "javascript",
    "mjs": "javascript",
    "cjs": "javascript",
    "ts": "typescript",
    "tsx": "typescript",
    "html": "html",
    "htm": "html",
    "css": "css",
    "py": "python",
    "yml": "yaml",
    "yaml": "yaml",
    "toml": "toml",
    "sh": "bash",
    "bash": "bash",
    "c": "c",
    "h": "c",
    "cpp": "cpp",
    "cc": "cpp",
    "hpp": "cpp",
    "cxx": "cpp",
    "rs": "rust",
    "go": "go",
    "java": "java",
    "rb": "ruby",
    "php": "php",
    "md": "markdown",
    "markdown": "markdown",
    "xml": "xml",
]

public func languageID(forFileExtension fileExtension: String) -> String? {
    fileExtensionToLanguageID[fileExtension.lowercased()]
}
