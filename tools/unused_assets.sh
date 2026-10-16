#!/usr/bin/env bash
# Fails on assets that nothing uses (#320): every file under assets/ must be named by its res://
# path in a script, scene, resource, content file or the project settings, be a buffer or texture
# that a used glTF names by its relative `uri`, or be a texture Godot's import extracts from a used
# model next to it. Each pack's own notes (SOURCE.md, its license) and Godot's .import files are
# left out: they come with the files they describe.
# Usage: tools/unused_assets.sh (from the repository's root)
set -euo pipefail

named=$(mktemp)
trap 'rm -f "$named"' EXIT

# Every asset named by its path.
{ git grep -ho 'res://assets/[^"'"'"')]*' -- '*.gd' '*.tscn' '*.tres' '*.godot' '*.cfg' '*.jsonc' \
  || true; } | sed 's#^res://##' | sort -u > "$named"
# Every buffer and texture a named glTF points at, next to it.
while read -r gltf; do
  dir=$(dirname "$gltf")
  { grep -o '"uri"[[:space:]]*:[[:space:]]*"[^"]*"' "$gltf" || true; } \
    | sed -E 's#.*"([^"]*)"$#\1#' | while read -r uri; do echo "${dir}/${uri}"; done
done < <(grep '\.gltf$' "$named" || true) >> "$named"
# Every texture Godot's import extracted from a named model next to it: its .import carries the
# generating importer's parameters, since no one added it by hand.
while read -r model; do
  dir=$(dirname "$model")
  { grep -l '^generator_parameters=' "$dir"/*.import 2>/dev/null || true; } | sed 's#\.import$##'
done < <(grep -E '\.(glb|gltf)$' "$named" || true) >> "$named"
sort -u -o "$named" "$named"

unused=$(git ls-files assets | grep -vE '\.import$|/SOURCE\.md$|/LICENSE[^/]*$' \
  | { grep -vxFf "$named" || true; })
if [ -n "$unused" ]; then
  while read -r file; do
    echo "::error file=${file}::${file} is in the repository but nothing uses it"
  done <<< "$unused"
  exit 1
fi
