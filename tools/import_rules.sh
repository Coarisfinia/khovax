#!/usr/bin/env bash
# Fails when a script reaches a file the wrong way (#375):
# - The core never depends on a slice: no script under core/ names a class_name declared under
#   slices/ or names a slices/ path in its code, with or without res://, so a path built from parts
#   ("res://" + "slices/tiles/data/") is refused too (AGENTS.md, "Vertical slices", #526).
# - Paths are absolute from res://: no string in a script starts with ./ or ../, no load or preload
#   of a path without its scheme, and no scene or resource names a file by a relative path.
# Comments don't count (a # outside strings, as the determinism check strips them), so the rules
# can be explained in them.
# Usage: tools/import_rules.sh (from the repository's root)
set -euo pipefail

failed=0

# A script's code without its comments.
code_of() {
  perl -pe 's/^((?:[^"'"'"'#]|"(?:\\.|[^"\\])*"|'"'"'(?:\\.|[^'"'"'\\])*'"'"')*)#.*$/$1/' "$1"
}

slice_classes=$({ git grep -h '^class_name ' -- 'slices/*.gd' || true; } \
  | awk '{print $2}' | paste -sd'|' -)
while IFS= read -r -d '' file; do
  code=$(code_of "$file")
  if [ -n "$slice_classes" ] && grep -nwE "$slice_classes" <<< "$code"; then
    echo "::error file=${file}::the core never depends on a slice: see the lines above"
    failed=1
  fi
  if grep -n 'slices/' <<< "$code"; then
    echo "::error file=${file}::the core never loads a slice's file: see the lines above"
    failed=1
  fi
done < <(git ls-files -z 'core/*.gd')

while IFS= read -r -d '' file; do
  code=$(code_of "$file")
  # Any string starting with ./ or ../, and every load or preload of a literal path that doesn't
  # start with its scheme (res://, user://, uid://), each found on its own.
  relative=$(
    grep -nE "[\"']\.\.?/" <<< "$code" || true
    grep -noE "\b(pre)?load\s*\(\s*[\"'][^\"']*" <<< "$code" | grep -vE "\(\s*[\"'][a-z]+://" || true
  )
  if [ -n "$relative" ]; then
    echo "$relative"
    echo "::error file=${file}::paths are absolute from res://: see the lines above"
    failed=1
  fi
done < <(git ls-files -z '*.gd')

if git grep -nE '\bpath="[^"]*"' -- '*.tscn' '*.tres' | grep -vE '\bpath="[a-z]+://'; then
  echo "::error::scenes and resources name files absolute from res://: see the lines above"
  failed=1
fi

exit "$failed"
