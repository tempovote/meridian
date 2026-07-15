#!/usr/bin/env bash
# Layer-purity gate (ADR 0006 / ARCHITECTURE.md §3.3):
# core packages must never import UI frameworks.
set -euo pipefail
cd "$(dirname "$0")/.."

PURE_PACKAGES=(DocumentCore SyntaxKit SearchKit FileKit)
PATTERN='^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+(AppKit|SwiftUI|UIKit|Cocoa)([[:space:]]|$)'

status=0
for pkg in "${PURE_PACKAGES[@]}"; do
  dir="Packages/${pkg}/Sources"
  if [ ! -d "$dir" ]; then
    echo "lint-imports: warning — ${dir} not found, skipping"
    continue
  fi
  if hits=$(grep -REn "$PATTERN" "$dir"); then
    echo "lint-imports: FAIL — UI framework import in ${pkg}:"
    echo "$hits"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "lint-imports: OK — core packages are UI-free"
fi
exit "$status"
