#!/usr/bin/env bash
# Fails when the export presets' file filters drift apart (#830): every preset in
# export_presets.cfg has the same include_filter, and presets with the same custom_features (the
# release builds, the e2e_test builds) have the same exclude_filter. A filter change then touches
# them all, or CI says which preset was missed.
# Usage: tools/export_filters_check.sh (from the repository's root)
set -euo pipefail

awk -F= '
  /^\[preset\.[0-9]+\]$/ { preset = $0; next }
  /^\[/ { preset = ""; next }
  preset == "" { next }
  $1 == "name" { name[preset] = $2 }
  $1 == "custom_features" { features[preset] = substr($0, length($1) + 2) }
  $1 == "include_filter" { include[preset] = substr($0, length($1) + 2) }
  $1 == "exclude_filter" { exclude[preset] = substr($0, length($1) + 2); order[++count] = preset }
  END {
    failed = 0
    for (i = 1; i <= count; i++) {
      p = order[i]
      if (include[p] != include[order[1]]) {
        printf "::error file=export_presets.cfg::preset %s has include_filter=%s, preset %s has %s\n", name[p], include[p], name[order[1]], include[order[1]]
        failed = 1
      }
      f = features[p]
      if (!(f in first)) { first[f] = p; continue }
      q = first[f]
      if (exclude[p] != exclude[q]) {
        printf "::error file=export_presets.cfg::preset %s has exclude_filter=%s, preset %s (same custom_features) has %s\n", name[p], exclude[p], name[q], exclude[q]
        failed = 1
      }
    }
    if (count == 0) { print "::error file=export_presets.cfg::no preset has an exclude_filter"; failed = 1 }
    exit failed
  }
' export_presets.cfg
