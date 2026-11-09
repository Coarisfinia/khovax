#!/usr/bin/env bash
# Runs the gdstyle the repository pins (#2215), for Linux and WSL, without installing anything
# system-wide: the first run downloads CI's release into the user's cache and checks its checksum.
# The version comes from tools/scoop/gdstyle.json and the checksum from CI's GDSTYLE_SHA256, the
# same two sources CI uses. Arguments go to gdstyle, which runs in the caller's folder.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $(uname -s)-$(uname -m) != Linux-x86_64 ]]; then
  echo "tools/gdstyle.sh: only for x86-64 Linux; elsewhere install tools/scoop/gdstyle.json" >&2
  exit 1
fi

version=$(jq -er .version "$root/tools/scoop/gdstyle.json")
sha256=$(sed -nE 's/^ *GDSTYLE_SHA256: *([0-9a-f]{64}) *$/\1/p' "$root/.github/workflows/ci.yml")
if [[ -z $sha256 ]]; then
  echo "tools/gdstyle.sh: no GDSTYLE_SHA256 in .github/workflows/ci.yml" >&2
  exit 1
fi

# Keyed by the checksum, and outside the repository so that every worktree shares one download.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/khovax/gdstyle/$version-$sha256"

if [[ ! -x $cache/gdstyle ]]; then
  mkdir -p "$cache"
  tmp=$(mktemp -d "$cache/download.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/gdstyle.tar.gz" \
    "https://github.com/atelico/gdstyle/releases/download/v${version}/gdstyle-x86_64-unknown-linux-gnu.tar.gz"
  echo "$sha256  $tmp/gdstyle.tar.gz" | sha256sum --check --quiet >&2
  tar xzf "$tmp/gdstyle.tar.gz" -C "$tmp" gdstyle
  # A rename, so a parallel run sees either no binary or a whole one.
  mv -f "$tmp/gdstyle" "$cache/gdstyle"
  rm -rf "$tmp"
  trap - EXIT
fi

exec "$cache/gdstyle" "$@"
