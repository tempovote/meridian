# Meridian

A native, Apple-Silicon-first source and text editor for macOS, in the spirit of Notepad++: opens instantly, handles gigabyte files without flinching, and offers serious text-manipulation power while looking and behaving like software Apple could have shipped.

Status: early development. The document engine (`DocumentCore` — persistent rope text storage, coordinate conversions, transactional edits with undo) is under active construction; no runnable editor app yet.

## Tooling

Development requires full Xcode (the `Testing`/`XCTest` modules are not in the
Command Line Tools). If `xcode-select -p` points at CommandLineTools, prefix
swift commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Lint gates (enforced in CI): SwiftFormat **0.62.1** (pinned in `ci.yml` — keep
your local install on the same version) and SwiftLint (latest, `--strict`).
Layer purity is enforced by `Scripts/lint-imports.sh`.
