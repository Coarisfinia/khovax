#!/usr/bin/env bash
# Prints the export template files (as named in Godot's templates archive) that the presets in
# export_presets.cfg need, one per line, so CI and the release unpack exactly those and nothing
# names the platforms twice. Usage: bash tools/export_templates.sh [export_presets.cfg]
set -euo pipefail
presets="${1:-export_presets.cfg}"

# Each preset's platform, and for the web whether it uses threads.
awk -F'"' '
  /^\[preset\.[0-9]+\]$/ { section = "preset" }
  /^\[preset\.[0-9]+\.options\]$/ { section = "options" }
  section == "preset" && /^platform="/ { print "platform " $2 }
  section == "options" && /^variant\/thread_support=/ { print "threads " substr($0, index($0, "=") + 1) }
' "$presets" | while read -r key value rest; do
  case "$key $value${rest:+ $rest}" in
    "platform Android"*) echo android_debug.apk; echo android_release.apk ;;
    "platform Windows Desktop") echo windows_release_x86_64.exe ;;
    "platform Linux") echo linux_release.x86_64 ;;
    "platform Web") web=1 ;;
    "threads false") [ "${web:-0}" = 1 ] && echo web_nothreads_release.zip; web=0 ;;
    "threads true") [ "${web:-0}" = 1 ] && echo web_release.zip; web=0 ;;
    "platform "*) echo "no export template is known for platform: $value $rest" >&2; exit 1 ;;
  esac
done | sort -u
