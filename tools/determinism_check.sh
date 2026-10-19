#!/usr/bin/env bash
# Fails when the simulation could stop being deterministic (AGENTS.md, "Architecture"). core/ and
# every slice's rules/ hold the rules: plain RefCounted classes (or classes of the rules, e.g.
# Feature) without nodes, input, time, engine or OS state, global randomness, frame delta, floats,
# or file and JSON access (#572: reading happens before a tick, never inside one).
# Comments are stripped first (a # outside strings, as tools/import_rules.sh does), so the rules
# can be explained in them.
# A whole file is exempt while its top comment lines carry the marker below with a reason in
# parentheses (owner, #515). It marks a workaround to fix later; a marker without a reason fails:
#   # TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (why this file can't pass yet)
# Usage: tools/determinism_check.sh (from the repository's root)
set -euo pipefail

# What the rules never use, one alternation per kind; add a kind as its own line.
forbidden_parts=(
  '\b(Node|Node2D|Node3D|CanvasItem|Control|Window|Viewport|Resource)\b'
  '\b(Input|InputMap|Time|Engine|OS|DisplayServer|RenderingServer|ProjectSettings)\.'
  '\b(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)\('
  '\bdelta\b'
  '\bfloat\b|[0-9]\.[0-9]|[0-9][eE][-+]?[0-9]'
  '\b(FileAccess|DirAccess|JSON)\b'
)
forbidden=$(IFS='|'; echo "${forbidden_parts[*]}")
marker='# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK'

failed=0

# A script's code without its comments.
code_of() {
  perl -pe 's/^((?:[^"'"'"'#]|"(?:\\.|[^"\\])*"|'"'"'(?:\\.|[^'"'"'\\])*'"'"')*)#.*$/$1/' "$1"
}

# The comment lines at the top of a file, before its first line of code.
header_of() {
  awk '/^[[:space:]]*(#|$)/ { print; next } { exit }' "$1"
}

# Whether a file is exempt: its header carries the marker with a reason, and no other marker sits
# anywhere in it. A marker without a reason, or one below the header, fails the file.
exempt() {
  local file=$1 markers
  markers=$(grep -cF 'IGNORE_DETERMINISM_CHECK' "$file" || true)
  if [ "$markers" = 1 ] && header_of "$file" | grep -qxE "${marker} \(.*[^ )].*\)"; then
    return 0
  fi
  if grep -nF 'IGNORE_DETERMINISM_CHECK' "$file"; then
    echo "::error file=${file}::the exemption marker sits in the top comment lines, with a reason:"\
      "${marker} (reason)"
    failed=1
  fi
  return 1
}

mapfile -t slice_rules < <(find slices -type d -name rules -print)
rules=(core "${slice_rules[@]}")
rule_classes=$(grep -rh '^class_name ' "${rules[@]}" | awk '{print $2}' | paste -sd'|' -)

while read -r file; do
  if exempt "$file"; then
    continue
  fi
  code=$(code_of "$file")
  if ! grep -qxE "extends (RefCounted|${rule_classes})" <<< "$code"; then
    echo "::error file=${file}::rules scripts extend RefCounted or a class of the rules"
    failed=1
  fi
  if grep -nE "$forbidden" <<< "$code"; then
    echo "::error file=${file}::the rules must stay deterministic: see the lines above"
    failed=1
  fi
done < <(find "${rules[@]}" -name '*.gd' | sort)

exit "$failed"
