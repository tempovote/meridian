#!/usr/bin/env bash
# Layer-purity gate (ADR 0006 / ARCHITECTURE.md §3.3):
# core packages must never import UI frameworks.
set -euo pipefail
cd "$(dirname "$0")/.."

PURE_PACKAGES=(DocumentCore SyntaxKit SearchKit FileKit)
PATTERN='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((class|struct|enum|protocol|typealias|func|var|let)[[:space:]]+)?(AppKit|SwiftUI|UIKit|Cocoa)([[:space:].]|$)'

status=0
for pkg in "${PURE_PACKAGES[@]}"; do
  for dir in "Packages/${pkg}/Sources" "Packages/${pkg}/Tests"; do
    if [ ! -d "$dir" ]; then
      if [ "$dir" = "Packages/${pkg}/Sources" ]; then
        echo "lint-imports: warning — ${dir} not found, skipping"
      fi
      continue
    fi
    if hits=$(grep -REn --include='*.swift' "$PATTERN" "$dir"); then
      echo "lint-imports: FAIL — UI framework import in ${pkg}:"
      echo "$hits"
      status=1
    fi
  done
done

if [ "$status" -eq 0 ]; then
  echo "lint-imports: OK — core packages are UI-free"
fi
exit "$status"
