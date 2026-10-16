#!/usr/bin/env bash
# Fails on code that nothing uses (#315). Godot already fails the script check on unused locals,
# parameters, private class variables and signals (project.godot); what it can't see across files
# is a function, class variable, constant or class that no other line in the project names. This
# lists every one declared at a script's top level and fails when its name appears nowhere but in its
# own declaration. Comments don't count as a use; strings do (a method called by name, a scene's
# property). Engine callbacks are used by the engine, so they're left out.
# Usage: tools/unused_code.sh (from the repository's root)
set -euo pipefail

# Methods the engine calls itself.
ENGINE='^_(ready|process|physics_process|init|static_init|notification|input|unhandled_input|unhandled_key_input|shortcut_input|gui_input|enter_tree|exit_tree|initialize|finalize|draw|to_string|get_configuration_warnings|validate_property|get_property_list|get|set|log_error|log_message)$'
DECLARATION='^(static )?func [A-Za-z_]|^(@[a-z_]+(\([^)]*\))? )*(static )?(var|const) [A-Za-z_]|^class_name [A-Za-z_]'

code=$(mktemp)
counts=$(mktemp)
trap 'rm -f "$code" "$counts"' EXIT

# Every script's code without its comments (a # outside strings, as the determinism check strips
# them), and the scenes and settings as they are.
git ls-files -z '*.gd' | xargs -0 perl -pe \
  's/^((?:[^"'"'"'#]|"(?:\\.|[^"\\])*"|'"'"'(?:\\.|[^'"'"'\\])*'"'"')*)#.*$/$1/' > "$code"
git ls-files -z '*.tscn' '*.tres' '*.godot' '*.cfg' | xargs -0 cat >> "$code"

# How often every word appears, counted once for the whole project.
grep -ow '[A-Za-z_][A-Za-z0-9_]*' "$code" | sort | uniq -c > "$counts"

# Each top-level declaration as file:line:name; a name used only where it's declared appears once
# in the whole project.
unused=$(git ls-files -z '*.gd' | xargs -0 grep -nE "$DECLARATION" \
  | sed -E 's#^([^:]+):([0-9]+):.*(func|var|const|class_name) ([A-Za-z_][A-Za-z0-9_]*).*#\1:\2:\4#' \
  | awk -v engine="$ENGINE" -v counts="$counts" '
      BEGIN { while ((getline line < counts) > 0) { split(line, w, " "); count[w[2]] = w[1] } }
      {
        split($0, part, ":")
        if (part[3] !~ engine && count[part[3]] <= 1) {
          printf "::error file=%s,line=%s::%s is declared but never used\n", part[1], part[2], part[3]
        }
      }')
if [ -n "$unused" ]; then
  echo "$unused"
  exit 1
fi
