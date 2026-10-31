"""Leaves the default pack's own files (#1860) out of the game's exports (#1965): every build carries
them in the default pack's .pck (#1941), which the game mounts, so exported beside it they'd be
carried twice. Adds every file default_pack.py gathers to each export preset's exclude_filter, in
export_presets.cfg, which CI runs before exporting; the committed presets stay as they are, so the
project still runs from its own files.

    uv run --locked --package khovax-game-pack-builder packages/game-pack-builder/exclude_default_pack.py
"""

import os
import re
import sys

from default_pack import GAME, listed
from game_shared import log
from game_shared.resource_packs import read_manifest

PRESETS = GAME / "export_presets.cfg"
EXCLUDE = re.compile(r'^exclude_filter="(.*)"$')
PRESET = re.compile(r"^\[preset\.[0-9]+\]$")


def excluded(text: str, files: list[str]) -> str:
    """The presets `text` with `files` added to every preset's exclude_filter."""
    lines = []
    for line in text.split("\n"):
        found = EXCLUDE.match(line)
        if found:
            patterns = [pattern for pattern in found.group(1).split(",") if pattern]
            added = [path for path in files if path not in patterns]
            line = f'exclude_filter="{",".join(patterns + added)}"'
        lines.append(line)
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) != 1:
        log.error("usage: exclude_default_pack.py")
        return 2
    os.chdir(GAME)
    files = listed(read_manifest())
    if any("," in path or '"' in path for path in files):
        log.error("a default pack file's path holds a comma or a quote, which a filter can't name")
        return 1
    text = PRESETS.read_text(encoding="utf-8")
    changed = excluded(text, files)
    presets = sum(1 for line in text.split("\n") if PRESET.match(line))
    filters = sum(1 for line in text.split("\n") if EXCLUDE.match(line))
    if presets == 0 or filters != presets:
        # Each preset must leave them out: one without its own exclude_filter would carry them.
        log.error(f"{PRESETS}: {filters} exclude_filter lines for {presets} presets")
        return 1
    PRESETS.write_text(changed, encoding="utf-8")
    print(f"{len(files)} files of the default pack left out of every export preset")
    return 0


if __name__ == "__main__":
    sys.exit(main())
