#!/usr/bin/env bash
# Checks the rule change files (#736): each file's name and frontmatter, and that the folder is
# append-only (#876): a file deleted or renamed would give the rules (RulesChanges, a digest of the
# names of the files in core/rules_changes/) an id that older rules may already have had. Whether
# a change needs a new file is the rules-compare job's (tools/rules_compare.sh).
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
  # No pr (#758): the squash commit that added the file names it (git log --diff-filter=A).
  if [ "$(sed -n '1p;3p' "$file" | paste -sd' ' -)" != '--- ---' ] \
    || ! sed -n 2p "$file" | grep -qx "issue: ${BASH_REMATCH[1]}"; then
    echo "::error file=${file}::its frontmatter is its issue (the file's number), nothing else (no pr: git log finds it)"
    failed=1
  fi
  if grep -q '/pull/[0-9]' "$file"; then
    echo "::error file=${file}::it links its issue, not its pull request (git log finds that)"
    failed=1
  fi
done

# Without rename detection, a renamed file shows as deleted (and another added).
while IFS= read -r path; do
  [ -n "$path" ] || continue
  echo "::error file=${path}::a rule change file is never deleted or renamed: the folder is append-only"
  failed=1
done <<< "$(git diff --no-renames --name-only --diff-filter=D "$base" HEAD -- "$folder")"

exit "$failed"
