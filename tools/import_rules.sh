#!/usr/bin/env bash
# Fails when a script reaches a file the wrong way (#375, #526). Each boundary is checked by class
# name (a class_name declared on the far side) and by path:
# - The core never depends on a slice: no script under core/ names a slice's class or a slices/
#   path in its code, with or without res://, so a path built from parts
#   ("res://" + "slices/tiles/data/") is refused too (AGENTS.md, "Vertical slices").
# - The rules stay pure: no script under core/ or a slice's rules/ names a class or a path of any
#   look/, ui/, view/, input/ or game/ folder, so the simulation never leans on what draws or
#   drives it.
# - Nothing outside tests/ reaches the tests, and nothing outside tools/ and tests/ reaches the
#   tools: no class of theirs, no tests/ or tools/ path.
# The folder paths are refused where they start a string or follow a /, with or without res://, so
# a path built from parts is caught too, while a message may still name a file in parentheses. The
# one exception is the test builds' mode, which plays the device flow from tests/
# (game/test_mode.gd): only its path is allowed there, never a test class.
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

# The class_names declared in the scripts the pathspecs match, as one alternation.
classes_in() {
  { git grep -h '^class_name ' -- "$@" || true; } | awk '{print $2}' | paste -sd'|' -
}

# Fails a file whose code names one of the classes or matches the path pattern (either may be
# empty, for none), with the rule it breaks.
refuse() {
  local file=$1 code=$2 classes=$3 path=$4 rule=$5 hits
  hits=$(
    if [ -n "$classes" ]; then grep -nwE "$classes" <<< "$code" || true; fi
    if [ -n "$path" ]; then grep -nE "$path" <<< "$code" || true; fi
  )
  if [ -n "$hits" ]; then
    echo "$hits"
    echo "::error file=${file}::${rule}: see the lines above"
    failed=1
  fi
}

slice_classes=$(classes_in 'slices/*.gd')
presentation_classes=$(classes_in ':(glob)**/look/**/*.gd' ':(glob)**/ui/**/*.gd' \
  ':(glob)**/view/**/*.gd' ':(glob)**/input/**/*.gd' ':(glob)**/game/**/*.gd')
test_classes=$(classes_in 'tests/*.gd')
tool_classes=$(classes_in 'tools/*.gd')
# Where a folder's path starts: at the start of a string, or after a /.
at="(^|[/\"'])"

while IFS= read -r -d '' file; do
  code=$(code_of "$file")
  case $file in
    core/*)
      refuse "$file" "$code" "$slice_classes" 'slices/' "the core never depends on a slice"
      ;;
  esac
  case $file in
    core/* | slices/*/rules/*)
      refuse "$file" "$code" "$presentation_classes" "${at}(look|ui|view|input|game)/" \
        "the rules never depend on what draws or drives them"
      ;;
  esac
  case $file in
    tests/*) ;;
    game/test_mode.gd)
      refuse "$file" "$code" "$test_classes" '' "nothing outside tests/ reaches the tests"
      ;;
    *)
      refuse "$file" "$code" "$test_classes" "${at}tests/" "nothing outside tests/ reaches the tests"
      ;;
  esac
  case $file in
    tests/* | tools/*) ;;
    *)
      refuse "$file" "$code" "$tool_classes" "${at}tools/" "the game never reaches tools/"
      ;;
  esac
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
