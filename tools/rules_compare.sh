#!/usr/bin/env bash
# Compares how this commit plays with how its parent plays (#876): two outcome reports
# (tests/replays/outcomes.gd), one from each commit's build. When they differ, the commit must add
# a rule change file to core/rules_changes/, or the check fails. Prints a Markdown summary for the
# job: which replay, and which checkpoint in it, diverges first.
# CI runs this script from the parent's checkout, so a pull request can't weaken its own check.
# What it can't compare fails too (#889): a reference replay removed or its inputs changed, the APK
# flow's scripts changed, or the outcome report itself changed. The owner allows that by labelling
# the pull request `outcomes-change`, which CI passes on as OUTCOMES_CHANGE=true only when the owner
# added it, with OUTCOMES_CHANGE_NOTE saying who did.
# Usage: [OUTCOMES_CHANGE=true] [OUTCOMES_CHANGE_NOTE=<who labelled it>] tools/rules_compare.sh
# <parent's report> <this commit's report> <parent> (from this commit's repository root; <parent>
# is the commit the parent's report was made from)
set -euo pipefail

parent_report=$1
head_report=$2
parent=$3
labelled=${OUTCOMES_CHANGE:-false}
label_note=${OUTCOMES_CHANGE_NOTE:-}
replays=tests/replays
folder=core/rules_changes
# The APK's flow and its headless runner.
flow_scripts=(tests/apk/apk_flow.gd tests/e2e/test_apk_flow.gd)

# A replay's inputs: everything but what a rehash writes (Replay.rehash), which a reference replay
# no longer holds (#876), as canonical JSON.
inputs() { git show "$1:$replays/$2" | jq -S 'del(.rules, .checkpoints, .features)'; }

# Where two reports first differ for one replay: its first differing checkpoint, else its final
# state; nothing when they match.
first_divergence() {
  jq -rn --slurpfile p "$parent_report" --slurpfile h "$head_report" --arg r "$1" '
    $p[0].replays[$r] as $a | $h[0].replays[$r] as $b
    | [($a.checkpoints, $b.checkpoints) | keys[] | tonumber] | unique
    | map(select($a.checkpoints[tostring] != $b.checkpoints[tostring])) as $ticks
    | if ($ticks | length) > 0 then "the checkpoint at tick \($ticks[0])"
      elif $a.final != $b.final then "the final state"
      else "" end'
}

# CI runs the parent's copy of this script, and falls back to the commit's own only while the
# parent has none (the pull request that added it). So no commit may remove it, or the next one
# could bring its own.
if ! git cat-file -e "HEAD:tools/rules_compare.sh" 2> /dev/null; then
  echo "::error::tools/rules_compare.sh is removed: the comparison with the parent can't go" >&2
  exit 1
fi

echo "### Rules: this commit compared with its parent"
echo
echo "| Played | Compared with the parent |"
echo "| --- | --- |"
diverged=()
unchecked=()
names=$(jq -rn --slurpfile p "$parent_report" --slurpfile h "$head_report" \
  '[$p[0].replays, $h[0].replays | keys[]] | unique[]')
while IFS= read -r name; do
  [ -n "$name" ] || continue
  in_parent=$(jq -r --arg r "$name" '.replays | has($r)' "$parent_report")
  in_head=$(jq -r --arg r "$name" '.replays | has($r)' "$head_report")
  if [ "$in_head" != true ]; then
    verdict="removed: nothing to compare"
    unchecked+=("\`$name\` is removed")
  elif [ "$in_parent" != true ]; then
    verdict="new: nothing to compare"
  elif [ "$(inputs "$parent" "$name")" != "$(inputs HEAD "$name")" ]; then
    verdict="its inputs changed: not compared"
    unchecked+=("\`$name\`'s inputs changed")
  else
    where=$(first_divergence "$name")
    if [ -z "$where" ]; then
      verdict="plays the same"
    else
      verdict="**differs**, first at $where"
      diverged+=("\`$name\` at $where")
    fi
  fi
  echo "| \`$name\` | $verdict |"
  if [[ $verdict == *"not compared"* || $verdict == *"nothing to compare"* ]]; then
    echo "::warning::$replays/$name: $verdict" >&2
  fi
done <<< "$names"

if ! git diff --quiet "$parent" HEAD -- "${flow_scripts[@]}"; then
  verdict="its script changed: not compared"
  unchecked+=("the APK flow's scripts changed")
  echo "::warning::the APK flow: $verdict" >&2
elif [ "$(jq -r .apk_flow.final "$parent_report")" = "$(jq -r .apk_flow.final "$head_report")" ]; then
  verdict="plays the same"
else
  verdict="**differs** in its final state"
  diverged+=("the APK flow's final state")
fi
echo "| the APK flow | $verdict |"
echo

if ! git diff --quiet "$parent" HEAD -- "$replays/outcomes.gd"; then
  unchecked+=("the outcome report (\`$replays/outcomes.gd\`) changed")
  echo "::warning::$replays/outcomes.gd changed: check that it still reports what the game does" >&2
fi

failed=0
if [ ${#unchecked[@]} -gt 0 ]; then
  echo "Not everything could be compared with the parent:"
  for what in "${unchecked[@]}"; do
    echo "- $what"
  done
  echo
  if [ "$labelled" = true ]; then
    echo "The owner labelled the pull request \`outcomes-change\`, so that's allowed."
  else
    echo "That needs the owner's label \`outcomes-change\` on the pull request (#889)."
    [ -z "$label_note" ] || echo "Here, $label_note."
    echo "::error::not everything could be compared with the parent, and the pull request isn't labelled outcomes-change" >&2
    failed=1
  fi
  echo
fi

# Without rename detection, a renamed file shows as deleted and added. The folder is append-only:
# a commit that deletes or renames a file declares nothing, even if it also adds one.
added=$(git diff --no-renames --name-only --diff-filter=A "$parent" HEAD -- "$folder")
deleted=$(git diff --no-renames --name-only --diff-filter=D "$parent" HEAD -- "$folder")
if [ ${#diverged[@]} -eq 0 ]; then
  echo "This commit plays like its parent."
  exit "$failed"
fi
echo "This commit plays differently from its parent. It diverges first in:"
for where in "${diverged[@]}"; do
  echo "- $where"
done
echo
if [ -n "$deleted" ]; then
  echo "It deletes or renames a rule change file, so it declares nothing: the folder is append-only."
elif [ -z "$added" ]; then
  echo "It adds no rule change file: add one to \`$folder/\` if that's intended (see RulesChanges), or find what changed the game."
else
  echo "It declares a rule change, so that's intended: check that the change above is the one declared in:"
  while IFS= read -r path; do
    echo "- \`$path\`"
  done <<< "$added"
  exit "$failed"
fi
echo "::error::this commit plays differently from its parent without a new file in ${folder}/" >&2
exit 1
