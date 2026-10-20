#!/usr/bin/env bash
# Fails on code that nothing uses (#315). Godot already fails the script check on unused locals,
# parameters, private class variables and signals (project.godot); what it can't see across files
# is a function, class variable, constant, enum or class that no other line in the project names.
# This lists every one declared at a script's top level (and every function of an inner class) and
# fails when its name appears nowhere but in its own declaration. Comments don't count as a use;
# strings do (a method called by name, a scene's property), and so does a scene naming a script's
# path for a class. A name shared with something else counts as used, so it never fails wrongly.
# Engine callbacks are used by the engine, so they're left out.
# Usage: tools/checks/unused_code.sh (from the repository's root)
set -euo pipefail

# Methods the engine calls itself.
ENGINE='^_(ready|process|physics_process|init|static_init|notification|enter_tree|exit_tree|initialize|finalize|input|unhandled_input|unhandled_key_input|shortcut_input|gui_input|input_event|mouse_enter|mouse_exit|draw|to_string|get|set|get_property_list|validate_property|property_can_revert|property_get_revert|get_configuration_warnings|get_minimum_size|get_drag_data|can_drop_data|drop_data|make_custom_tooltip|has_point|integrate_forces|log_error|log_message)$'
# A declaration: annotations first (`@export_range(0, 12)`, `@onready`, `@rpc("any_peer")`), then
# `static`, then the keyword and the name. Functions may be indented, inside an inner class.
DECLARATION='^((@[a-z_]+(\([^)]*\))?) )*(static )?(var|const|func|class_name|class|enum) [A-Za-z_]|^[[:space:]]+(static )?func [A-Za-z_]'

code=$(mktemp)
counts=$(mktemp)
scripts=$(mktemp)
trap 'rm -f "$code" "$counts" "$scripts"' EXIT

# Every script's code without its comments (a # outside strings, as the determinism check strips
# them), and the scenes and settings as they are.
git ls-files -z '*.gd' | xargs -0 perl -pe \
  's/^((?:[^"'"'"'#]|"(?:\\.|[^"\\])*"|'"'"'(?:\\.|[^'"'"'\\])*'"'"')*)#.*$/$1/' > "$code"
git ls-files -z '*.tscn' '*.tres' '*.godot' '*.cfg' | xargs -0 cat >> "$code"

# How often every word appears, counted once for the whole project, and every script a scene or
# another script names by path.
{ grep -ow '[A-Za-z_][A-Za-z0-9_]*' "$code" || true; } | sort | uniq -c > "$counts"
{ grep -o 'res://[^"]*\.gd' "$code" || true; } | sed 's#^res://##' | sort -u > "$scripts"

# Each declaration as file:line:keyword:name, the name taken right after its keyword at the start
# of the line, never from a default value further on.
unused=$( { git ls-files -z '*.gd' | xargs -0 grep -nE "$DECLARATION" || true; } \
  | sed -E 's#^([^:]+):([0-9]+):[[:space:]]*((@[a-z_]+(\([^)]*\))?) )*(static )?(var|const|func|class_name|class|enum) ([A-Za-z_][A-Za-z0-9_]*).*#\1:\2:\7:\8#' \
  | awk -v engine="$ENGINE" -v counts="$counts" -v scripts="$scripts" '
      BEGIN {
        while ((getline line < counts) > 0) { split(line, w, " "); count[w[2]] = w[1] }
        while ((getline path < scripts) > 0) { attached[path] = 1 }
      }
      {
        split($0, part, ":")
        file = part[1]; kind = part[3]; name = part[4]
        if (name ~ engine || count[name] > 1 || (kind == "class_name" && file in attached)) {
          next
        }
        printf "::error file=%s,line=%s::%s is declared but never used\n", file, part[2], name
      }')
if [ -n "$unused" ]; then
  echo "$unused"
  exit 1
fi
