#!/usr/bin/env bash
# Fails when a tracked path repeats a folder name (#442): slices/tiles/data/tiles/ is refused,
# slices/tiles/data/foo/ is fine. Only folders count, not the file's own name.
# Usage: tools/checks/repeated_folders.sh (from the repository's root)
set -euo pipefail

repeated=$(git ls-files | awk -F/ '{
  split("", seen)
  for (i = 1; i < NF; i++) {
    if ($i in seen) { print; next }
    seen[$i] = 1
  }
}')
if [ -n "$repeated" ]; then
  while IFS= read -r path; do
    echo "::error file=${path}::its path repeats a folder name"
  done <<< "$repeated"
  exit 1
fi
