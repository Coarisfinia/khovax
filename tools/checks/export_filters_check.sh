#!/usr/bin/env bash
# Fails when the export presets' file filters drift apart (#830): every preset in
# export_presets.cfg has the same include_filter, and presets with the same custom_features (the
# release builds, the e2e_test builds) have the same exclude_filter. A filter change then touches
# them all, or CI says which preset was missed. Every exclude_filter also names tools/*: the
# developer tools run from the project, never from a build (#921).
# Usage: tools/checks/export_filters_check.sh (from the repository's root)
set -euo pipefail

awk -F= '
  /^\[preset\.[0-9]+\]$/ { preset = $0; order[++count] = preset; next }
  /^\[/ { preset = ""; next }
  preset == "" { next }
  $1 == "name" { name[preset] = $2 }
  $1 == "custom_features" { features[preset] = substr($0, length($1) + 2) }
  $1 == "include_filter" { include[preset] = substr($0, length($1) + 2) }
  $1 == "exclude_filter" { exclude[preset] = substr($0, length($1) + 2) }
  END {
    failed = 0
    for (i = 1; i <= count; i++) {
      p = order[i]
      if (!(p in include) || !(p in exclude)) {
        printf "::error file=export_presets.cfg::preset %s lacks an include_filter or an exclude_filter\n", p
        failed = 1
        continue
      }
      if (exclude[p] !~ /^"(.*,)?tools\/\*(,.*)?"$/) {
        printf "::error file=export_presets.cfg::preset %s has exclude_filter=%s without tools/*\n", name[p], exclude[p]
        failed = 1
      }
      if (ref == "") ref = p
      if (include[p] != include[ref]) {
        printf "::error file=export_presets.cfg::preset %s has include_filter=%s, preset %s has %s\n", name[p], include[p], name[ref], include[ref]
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
    if (count == 0) { print "::error file=export_presets.cfg::it has no preset"; failed = 1 }
    exit failed
  }
' export_presets.cfg
