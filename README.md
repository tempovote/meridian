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

## Nightly verification

`nightly.yml` runs a deeper pass than per-PR CI: a 1M-operation buffer/undo
fuzz run with a fresh, logged random seed; the Unicode edge corpus at full
scale (a 100 MB single line); the rope benchmarks at ×10 workload/budget; and
a Thread Sanitizer pass. Benchmark budgets are only asserted in release
builds (`swift test -c release`) — a debug `swift test` run is a tiny smoke
check with no assertions — so per-PR CI also runs a release-mode perf smoke
(`perf-smoke` in `ci.yml`, default scale) to catch regressions before they
reach nightly. Four env vars tune the runs: `MERIDIAN_FUZZ_SEED` (fuzz PRNG
seed), `MERIDIAN_FUZZ_OPS` (fuzz operation count), `MERIDIAN_CORPUS_SCALE`
(`full` for the 100 MB corpus), and `MERIDIAN_PERF_SCALE` (benchmark
workload/budget multiplier). A manual `workflow_dispatch` run with
`fuzz_ops=10000000` is the designated M1 exit-review run.
