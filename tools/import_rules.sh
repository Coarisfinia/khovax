#!/usr/bin/env bash
# Fails when a script reaches a file the wrong way (#375, #526). Each boundary is checked by class
# name (a class_name declared on the far side) and by path:
# - The core never depends on a slice: no script under core/ names a slice's class or a slices/
#   path in its code, with or without res://, so a path built from parts
#   ("res://" + "slices/tiles/data/") is refused too (AGENTS.md, "Vertical slices").
# - The rules stay pure: no script under core/ or a slice's rules/ names a class or a path of any
#   look/, ui/, input/ or game/ folder, so the simulation never leans on what draws or
#   drives it.
# - Lasting data stays apart from what shows and drives the game (#827): no script in a slice's
#   meta/ names a class or a path of any look/, ui/ or input/ folder; what ties lasting data to the
#   running session lives beside what it ties (#831).
# - The slices form no cycle (#821): SLICE_ORDER below declares their order once, and a slice's
#   scripts, scenes and resources name only the classes and paths of slices before it. A new slice
#   takes its place in the order. Today's back-edges wait in SLICE_EXEMPT, each with the issue that
#   drops it, and an exemption no longer used fails too, so the list only shrinks.
# - game/ is where the game is wired together, so it may reach any slice, and nothing but the tests
#   and the tools reaches back into it (owner, #514): no script elsewhere names a game/ class or a
#   game/ path, and no scene or resource outside game/ names a game/ file. The slices see the
#   driver only as a Session.
# - Nothing outside tests/ reaches the tests, and nothing outside tools/ and tests/ reaches the
#   tools: no class of theirs, no tests/ or tools/ path.
# The folder paths are refused where they start a string or follow a /, with or without res://, so
# a path built from parts is caught too, while a message may still name a file in parentheses. The
# test builds' mode takes its flow's path from the environment or a project setting (#551).
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
  ':(glob)**/input/**/*.gd' ':(glob)**/game/**/*.gd')
view_classes=$(classes_in ':(glob)**/look/**/*.gd' ':(glob)**/ui/**/*.gd' ':(glob)**/input/**/*.gd')
# The slices, each after every slice it names (#821).
SLICE_ORDER=(
  camera music credits hiding movement entering exits paths loot board fog action_buttons triggers
  players npcs trail species health wild_monsters tiles outbox controls settings texts factions
  survey menu
  domination enrage domination_loot companions gear chests damage_numbers harvest dialogs
  profile quests revive_items blueprints might
)
# The back-edges still waiting ("slice>later slice" = the issue that drops it).
declare -A SLICE_EXEMPT=(
  [board>blueprints]=851 [board>controls]=851 [board>profile]=851 [board>tiles]=851
  [controls>profile]=851 [controls>revive_items]=851
  [factions>menu]=851 [factions>profile]=851
  [fog>blueprints]=851
  [gear>profile]=851
  [hiding>wild_monsters]=851
  [loot>menu]=851 [loot>profile]=851
  [menu>gear]=851 [menu>might]=851 [menu>profile]=851 [menu>quests]=851
  [players>health]=851 [players>profile]=851
  [profile>quests]=851 [profile>revive_items]=851
  [quests>blueprints]=851
  [settings>damage_numbers]=851 [settings>menu]=851 [settings>survey]=851
  [species>menu]=851 [species>profile]=851 [species>texts]=851
  [survey>profile]=851 [survey>quests]=851
  [texts>factions]=851 [texts>gear]=851
  [trail>domination]=851
  [wild_monsters>companions]=851 [wild_monsters>controls]=851 [wild_monsters>domination]=851
)
# Per slice: its own classes, and the later slices' classes and folder names it may not name.
declare -A own_classes later_classes later_slices exemption_used back_edge
for slice in "${SLICE_ORDER[@]}"; do
  own_classes[$slice]=$(classes_in "slices/$slice/*.gd")
done
for ((i = 0; i < ${#SLICE_ORDER[@]}; i++)); do
  slice=${SLICE_ORDER[i]}
  for later in "${SLICE_ORDER[@]:i+1}"; do
    if [ -n "${SLICE_EXEMPT[$slice>$later]:-}" ]; then
      back_edge[$slice>$later]=1
      continue
    fi
    later_slices[$slice]+="${later_slices[$slice]:+|}$later"
    if [ -n "${own_classes[$later]}" ]; then
      later_classes[$slice]+="${later_classes[$slice]:+|}${own_classes[$later]}"
    fi
  done
done

game_classes=$(classes_in 'game/*.gd')
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
      refuse "$file" "$code" "$presentation_classes" "${at}(look|ui|input|game)/" \
        "the rules never depend on what draws or drives them"
      ;;
  esac
  case $file in
    slices/*/meta/*)
      refuse "$file" "$code" "$view_classes" "${at}(look|ui|input)/" \
        "lasting data never depends on what shows or drives the game"
      ;;
  esac
  case $file in
    slices/*)
      slice=${file#slices/}
      slice=${slice%%/*}
      if [ -n "${own_classes[$slice]+set}" ]; then
        refuse "$file" "$code" "${later_classes[$slice]:-}" \
          "${at}slices/(${later_slices[$slice]:-^$})/" \
          "a slice names only the slices before it in SLICE_ORDER"
        for exempt in "${!SLICE_EXEMPT[@]}"; do
          [ "${exempt%>*}" = "$slice" ] || continue
          later=${exempt#*>}
          if { [ -n "${own_classes[$later]}" ] && grep -qwE "${own_classes[$later]}" <<< "$code"; } ||
            grep -qE "${at}slices/$later/" <<< "$code"; then
            exemption_used[$exempt]=1
          fi
        done
      fi
      ;;
  esac
  case $file in
    game/* | tests/* | tools/*) ;;
    *)
      refuse "$file" "$code" "$game_classes" "${at}game/" "nothing outside game/ reaches game/"
      ;;
  esac
  case $file in
    tests/*) ;;
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

while IFS= read -r -d '' file; do
  slice=${file#slices/}
  slice=${slice%%/*}
  if [ -n "${later_slices[$slice]:-}" ] &&
    grep -nE "res://slices/(${later_slices[$slice]})/" "$file"; then
    echo "::error file=${file}::a slice names only the slices before it in SLICE_ORDER: see the lines above"
    failed=1
  fi
  for exempt in "${!SLICE_EXEMPT[@]}"; do
    if [ "${exempt%>*}" = "$slice" ] && grep -q "res://slices/${exempt#*>}/" "$file"; then
      exemption_used[$exempt]=1
    fi
  done
done < <(git ls-files -z 'slices/*.tscn' 'slices/*.tres')

# Every slice has its place in the order, every place a slice, and every exemption is still used.
for dir in slices/*/; do
  slice=${dir#slices/}
  slice=${slice%/}
  if [ -z "${own_classes[$slice]+set}" ]; then
    echo "::error::slices/$slice has no place in SLICE_ORDER (tools/import_rules.sh)"
    failed=1
  fi
done
for slice in "${SLICE_ORDER[@]}"; do
  if [ ! -d "slices/$slice" ]; then
    echo "::error::SLICE_ORDER names slices/$slice, which doesn't exist (tools/import_rules.sh)"
    failed=1
  fi
done
for exempt in "${!SLICE_EXEMPT[@]}"; do
  if [ -z "${exemption_used[$exempt]:-}" ] || [ -z "${back_edge[$exempt]:-}" ]; then
    echo "::error::SLICE_EXEMPT's $exempt is no longer needed: drop it (tools/import_rules.sh)"
    failed=1
  fi
done

if git grep -n 'res://game/' -- '*.tscn' '*.tres' ':!game/' ':!tests/' ':!tools/'; then
  echo "::error::nothing outside game/ reaches game/: see the lines above"
  failed=1
fi

exit "$failed"
