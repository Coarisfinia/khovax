#!/usr/bin/env bash
# Compares how this commit plays with how its parent plays (#876): two outcome reports
# (tests/replays/outcomes.gd), one from each commit's build. When they differ, the commit must add
# a rule change file to core/rules_changes/, or the check fails. Prints a Markdown summary for the
# job: which replay, and which checkpoint in it, diverges first.
# CI runs this script from the parent's checkout, so a pull request can't weaken its own check.
# Usage: tools/rules_compare.sh <parent's report> <this commit's report> <parent>
# (from this commit's repository root; <parent> is the commit the parent's report was made from)
set -euo pipefail

parent_report=$1
head_report=$2
parent=$3
replays=tests/replays
folder=core/rules_changes
# The APK's flow and its headless runner. A changed EXPECTED_HASH alone isn't a changed flow: the
# rules changes check (tools/rules_changes_check.sh) owns it until it goes (#876, step 5).
flow_scripts=(tests/apk/apk_flow.gd tests/e2e/test_apk_flow.gd)
flow_output='^const EXPECTED_HASH'

# A replay's inputs: everything but what a rehash writes (Replay.rehash), as canonical JSON.
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
names=$(jq -rn --slurpfile p "$parent_report" --slurpfile h "$head_report" \
  '[$p[0].replays, $h[0].replays | keys[]] | unique[]')
while IFS= read -r name; do
  [ -n "$name" ] || continue
  in_parent=$(jq -r --arg r "$name" '.replays | has($r)' "$parent_report")
  in_head=$(jq -r --arg r "$name" '.replays | has($r)' "$head_report")
  if [ "$in_head" != true ]; then
    verdict="removed: nothing to compare"
  elif [ "$in_parent" != true ]; then
    verdict="new: nothing to compare"
  elif [ "$(inputs "$parent" "$name")" != "$(inputs HEAD "$name")" ]; then
    verdict="its inputs changed: not compared"
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

if ! git diff --quiet -I "$flow_output" "$parent" HEAD -- "${flow_scripts[@]}"; then
  verdict="its script changed: not compared"
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
  echo "::warning::$replays/outcomes.gd changed: check that it still reports what the game does" >&2
  echo "The outcome report itself (\`$replays/outcomes.gd\`) changed: check in the diff that it still reports what the game does."
  echo
fi

# Without rename detection, a renamed file shows as deleted and added. The folder is append-only:
# a commit that deletes or renames a file declares nothing, even if it also adds one.
added=$(git diff --no-renames --name-only --diff-filter=A "$parent" HEAD -- "$folder")
deleted=$(git diff --no-renames --name-only --diff-filter=D "$parent" HEAD -- "$folder")
if [ ${#diverged[@]} -eq 0 ]; then
  echo "This commit plays like its parent."
  exit 0
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
  exit 0
fi
echo "::error::this commit plays differently from its parent without a new file in ${folder}/" >&2
exit 1
