#!/bin/bash
# Vendors tree-sitter grammar C sources + highlight queries listed in
# Scripts/grammar-manifest.tsv. Usage:
#   Scripts/vendor-grammars.sh <languageID> [<languageID> ...]
# Must be run from the repo root.
set -euo pipefail

MANIFEST="Scripts/grammar-manifest.tsv"
RAW_BASE="https://raw.githubusercontent.com"
GRAMMARS_DIR="Grammars/Sources"
QUERIES_DIR="Packages/SyntaxKit/Sources/SyntaxKit/Resources"

if [ ! -f "$MANIFEST" ]; then
  echo "error: $MANIFEST not found — run this script from the repo root" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <languageID> [<languageID> ...]" >&2
  exit 1
fi

vendor_one() {
  local id=$1
  local row
  row=$(awk -F'\t' -v id="$id" '$1 == id { print }' "$MANIFEST")

  if [ -z "$row" ]; then
    echo "error: no manifest row found for languageID '$id'" >&2
    exit 1
  fi

  local repo sha source_path has_scanner queries_path
  repo=$(echo "$row" | cut -f2)
  sha=$(echo "$row" | cut -f3)
  source_path=$(echo "$row" | cut -f4)
  has_scanner=$(echo "$row" | cut -f5)
  queries_path=$(echo "$row" | cut -f6)

  local cap
  cap=$(echo "${id:0:1}" | tr '[:lower:]' '[:upper:]')${id:1}
  local target_dir="$GRAMMARS_DIR/TreeSitter${cap}"

  echo "Vendoring $id from $repo@$sha ..."
  mkdir -p "$target_dir/tree_sitter"

  curl -sf -o "$target_dir/parser.c" "$RAW_BASE/$repo/$sha/$source_path/parser.c"

  if [ "$has_scanner" = "yes" ]; then
    curl -sf -o "$target_dir/scanner.c" "$RAW_BASE/$repo/$sha/$source_path/scanner.c"
  fi

  curl -sf -o "$target_dir/tree_sitter/parser.h" "$RAW_BASE/$repo/$sha/$source_path/tree_sitter/parser.h"
  curl -sf -o "$target_dir/tree_sitter/alloc.h" "$RAW_BASE/$repo/$sha/$source_path/tree_sitter/alloc.h" || rm -f "$target_dir/tree_sitter/alloc.h"
  curl -sf -o "$target_dir/tree_sitter/array.h" "$RAW_BASE/$repo/$sha/$source_path/tree_sitter/array.h" || rm -f "$target_dir/tree_sitter/array.h"

  mkdir -p "$QUERIES_DIR/$id"
  curl -sf -o "$QUERIES_DIR/$id/highlights.scm" "$RAW_BASE/$repo/$sha/$queries_path"

  echo "Vendored $id -> $target_dir, $QUERIES_DIR/$id/highlights.scm"
}

for lang_id in "$@"; do
  vendor_one "$lang_id"
done
