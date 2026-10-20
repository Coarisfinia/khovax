#!/usr/bin/env bash
# Godot's script check on every tracked script, warnings as errors (project.godot), one Godot per
# script as before but as many at once as the machine has cores (#923). Every failing script is
# named, not only the first. A script fails when Godot exits non-zero or when its output has an
# ERROR: line, even with exit 0 (such as a load cycle through a preloaded scene, #964).
# Usage: [GODOT=<binary>] tools/script_check.sh (from the repository root; GODOT defaults to godot)
set -euo pipefail

export GODOT=${GODOT:-godot}
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
export logs

# Checks one script; its output goes to <logs>/<n>.log, and a failure writes <logs>/<n>.fail with
# the reason. Always exits 0, so xargs runs every check.
check() {
  local n=$1 script=$2 output
  if ! output=$(timeout 60 "$GODOT" --headless --path . --check-only -s "res://${script}" 2>&1); then
    echo "fails Godot's script check" > "${logs}/${n}.fail"
  elif grep -q '^ERROR:' <<< "${output}"; then
    echo "Godot's script check logs an error" > "${logs}/${n}.fail"
  fi
  printf '%s\n' "${output}" > "${logs}/${n}.log"
}
export -f check

mapfile -t scripts < <(git ls-files '*.gd')
# A check that dies makes xargs fail; the loop below still runs and names its script.
for n in "${!scripts[@]}"; do printf '%s\0%s\0' "$n" "${scripts[$n]}"; done \
  | xargs -0 -n 2 -P "$(nproc)" bash -c 'check "$1" "$2"' _ \
  || true

# The logs in the scripts' order, so the output doesn't interleave.
failed=0
for n in "${!scripts[@]}"; do
  # A check that never finished (no log) fails too.
  [ -e "${logs}/${n}.log" ] || echo "the script check didn't finish" > "${logs}/${n}.fail"
  cat "${logs}/${n}.log" 2> /dev/null || true
  if [ -e "${logs}/${n}.fail" ]; then
    echo "::error file=${scripts[$n]}::$(cat "${logs}/${n}.fail")"
    failed=$((failed + 1))
  fi
done
echo "${#scripts[@]} scripts checked, ${failed} failed."
[ "$failed" -eq 0 ]
