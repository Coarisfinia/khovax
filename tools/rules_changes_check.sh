#!/usr/bin/env bash
# Fails when a golden replay changed without a new rule change file (#736): a changed replay means
# the game plays out differently, and the rules version (RulesChanges, the number of files in
# core/rules_changes/) has to move with it. Also checks each file's name and frontmatter.
# Usage: tools/rules_changes_check.sh <base> (from the repository's root; <base> is the commit the
# change is compared with, e.g. HEAD^1 of a pull request's merge commit)
set -euo pipefail

base=$1
folder=core/rules_changes
failed=0

for file in "$folder"/*; do
  name=$(basename "$file")
  if [[ ! $name =~ ^([0-9]+)-[a-z0-9-]+\.md$ ]]; then
    echo "::error file=${file}::a rule change file is named <issue>-<slug>.md"
    failed=1
    continue
  fi
  if [ "$(sed -n '1p;4p' "$file" | paste -sd' ' -)" != '--- ---' ] \
    || ! sed -n 2p "$file" | grep -qx "issue: ${BASH_REMATCH[1]}" \
    || ! sed -n 3p "$file" | grep -qxE 'pr: [0-9]+'; then
    echo "::error file=${file}::its frontmatter is its issue (the file's number) and its pr, nothing else"
    failed=1
  fi
done

changed=$(git diff --name-only --diff-filter=M "$base" HEAD -- 'tests/replays/*.replay')
added=$(git diff --name-only --diff-filter=A "$base" HEAD -- "$folder")
if [ -n "$changed" ] && [ -z "$added" ]; then
  while IFS= read -r path; do
    echo "::error file=${path}::the rules changed: add a file to ${folder}/ (see RulesChanges)"
  done <<< "$changed"
  failed=1
fi

exit "$failed"
