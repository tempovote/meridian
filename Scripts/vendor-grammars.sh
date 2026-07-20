#!/bin/bash
# Vendors tree-sitter grammar C sources + highlight queries listed in
# Scripts/grammar-manifest.tsv. Usage:
#   Scripts/vendor-grammars.sh <languageID> [<languageID> ...]
# Must be run from the repo root.
#
# Known gap: this script does NOT vendor every file a grammar needs.
#   - SPM's publicHeadersPath requires a hand-shaped
#     Grammars/Sources/TreeSitter<Cap>/include/<lang>.h for every grammar;
#     this script generates that file for you (see generate_include_header
#     below), but if the upstream grammar exposes more than one
#     tree_sitter_* entry point (e.g. a *_only variant) you'll still need
#     to hand-edit it.
#   - Some grammars' scanner.c #includes a same-repo file that isn't part
#     of the manifest's fetch set (parser.c/scanner.c/tree_sitter/*.h/
#     highlights.scm) and has to be fetched manually. Precedent already in
#     this tree: TypeScript/PHP/XML need common/scanner.h (plus editing the
#     #include path in scanner.c to match where it landed); HTML needs
#     tag.h (no edit); YAML pulls in schema.core.c via a
#     `#include _file(YAML_SCHEMA)` macro (no edit). The script below
#     prints a best-effort warning when it detects this, but it cannot
#     fetch the file for you — do that by hand from the same repo/SHA.
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

generate_include_header() {
  local id=$1
  local header_path=$2

  if [ -f "$header_path" ]; then
    # Never regenerate an existing header — hand-authored ones (e.g. Swift's,
    # which uses a slightly different signature) must be left untouched.
    return
  fi

  local id_upper
  id_upper=$(echo "$id" | tr '[:lower:]' '[:upper:]')

  mkdir -p "$(dirname "$header_path")"
  cat > "$header_path" <<EOF
#ifndef TREE_SITTER_${id_upper}_H_
#define TREE_SITTER_${id_upper}_H_

typedef struct TSLanguage TSLanguage;

#ifdef __cplusplus
extern "C" {
#endif

const TSLanguage *tree_sitter_${id}(void);

#ifdef __cplusplus
}
#endif

#endif // TREE_SITTER_${id_upper}_H_
EOF
}

warn_on_unvendored_scanner_includes() {
  local id=$1
  local scanner_path=$2
  local target_dir=$3

  local include_line inc
  while IFS= read -r include_line; do
    inc=$(echo "$include_line" | sed -E 's/^#include[[:space:]]+//')
    case "$inc" in
      '"tree_sitter/parser.h"' | '"tree_sitter/alloc.h"' | '"tree_sitter/array.h"')
        ;;
      *)
        echo "warning: $id's scanner.c includes $inc which was not vendored — fetch it manually from the same repo/SHA into $target_dir and adjust the #include path if needed (see: TypeScript/PHP/XML's common/scanner.h, HTML's tag.h, YAML's schema.core.c for precedent)" >&2
        ;;
    esac
  done < <(grep -E '^#include[[:space:]]+[^<]' "$scanner_path" || true)
}

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
    warn_on_unvendored_scanner_includes "$id" "$target_dir/scanner.c" "$target_dir"
  fi

  curl -sf -o "$target_dir/tree_sitter/parser.h" "$RAW_BASE/$repo/$sha/$source_path/tree_sitter/parser.h"
  curl -sf -o "$target_dir/tree_sitter/alloc.h" "$RAW_BASE/$repo/$sha/$source_path/tree_sitter/alloc.h" || rm -f "$target_dir/tree_sitter/alloc.h"
  curl -sf -o "$target_dir/tree_sitter/array.h" "$RAW_BASE/$repo/$sha/$source_path/tree_sitter/array.h" || rm -f "$target_dir/tree_sitter/array.h"

  mkdir -p "$QUERIES_DIR/$id"
  curl -sf -o "$QUERIES_DIR/$id/highlights.scm" "$RAW_BASE/$repo/$sha/$queries_path"

  generate_include_header "$id" "$target_dir/include/$id.h"

  echo "Vendored $id -> $target_dir, $QUERIES_DIR/$id/highlights.scm"
}

for lang_id in "$@"; do
  vendor_one "$lang_id"
done
