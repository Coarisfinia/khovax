#!/usr/bin/env bash
# Compares two headless load test reports (tools/godot/load_test.gd, #101) for CI (#303): this branch's
# and, on a pull request, its base's, both measured in the same job on the same runner. Prints a
# Markdown table for the job summary, and fails when this branch's mean tick is more than SLOWER
# times the base's (plus a small floor, since a tick is microseconds and runners jitter).
# Usage: tools/replays/load_test_compare.sh <this branch's report> [<base's report>]
set -euo pipefail

SLOWER=1.5
FLOOR_US=50

head_report=$1
base_report=${2:-}

# The mean tick in microseconds, and every feature's share, from one report.
mean_of() { sed -n 's/^ *tick: mean \([0-9][0-9]*\.[0-9]\) us.*/\1/p' "$1"; }
features_of() { sed -n 's/^ *feature \([a-z0-9_][a-z0-9_]*\): \([0-9][0-9]*\.[0-9]\) us per tick$/\1 \2/p' "$1"; }

if ! grep -qE '^end state hash -?[0-9]+, same in both passes$' "$head_report"; then
  echo "The load test didn't end with both passes in the same state: it failed, or the simulation isn't deterministic."
  exit 1
fi
head_mean=$(mean_of "$head_report")
if ! [[ "$head_mean" =~ ^[0-9]+\.[0-9]$ ]]; then
  echo "The load test's report has no mean tick."
  exit 1
fi

if [ -z "$base_report" ] || [ ! -s "$base_report" ] || [ -z "$(mean_of "$base_report")" ]; then
  echo "### Load test"
  echo
  echo "| | This branch |"
  echo "|---|---|"
  echo "| A tick, mean | ${head_mean} µs |"
  while read -r feature share; do
    echo "| Feature ${feature} | ${share} µs |"
  done < <(features_of "$head_report")
  exit 0
fi

base_mean=$(mean_of "$base_report")
echo "### Load test, against the base"
echo
echo "| | Base | This branch |"
echo "|---|---|---|"
echo "| A tick, mean | ${base_mean} µs | ${head_mean} µs |"
while read -r feature share; do
  base_share=$(features_of "$base_report" | awk -v f="$feature" '$1 == f { print $2 }')
  echo "| Feature ${feature} | ${base_share:--} µs | ${share} µs |"
done < <(features_of "$head_report")

if awk -v h="$head_mean" -v b="$base_mean" -v s="$SLOWER" -v f="$FLOOR_US" \
  'BEGIN { exit !(h > b * s + f) }'; then
  echo
  echo "**The simulation got slower:** a mean tick of ${head_mean} µs against the base's ${base_mean} µs."
  exit 1
fi
