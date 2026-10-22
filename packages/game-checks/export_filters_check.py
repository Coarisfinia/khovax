"""Fails when the export presets' file filters drift apart (#830): every preset in
export_presets.cfg has the same include_filter, and presets with the same custom_features (the
release builds, the e2e_test builds) have the same exclude_filter. A filter change then touches
them all, or CI says which preset was missed. Every exclude_filter also names tools/*: the
developer tools run from the project, never from a build (#921). The web presets share their
html/head_include, the loading page (#925): the web e2e checks it on the Web Test build only.

    uv run --locked --package khovax-game-checks packages/game-checks/export_filters_check.py
"""

import os
import re
import sys
from pathlib import Path

from game_shared import log

# A preset's keys are in [preset.N] and its options in [preset.N.options]; both count as preset N.
PRESET = re.compile(r"\[preset\.([0-9]+)(\.options)?\]")
TOOLS_EXCLUDED = re.compile(r'"(.*,)?tools/\*(,.*)?"')
KEYS = (
    "name",
    "platform",
    "custom_features",
    "include_filter",
    "exclude_filter",
    "html/head_include",
)


def presets(text: str) -> dict[str, dict[str, str]]:
    """Each preset's keys that the check reads, by its [preset.N] header, in the file's order."""
    found: dict[str, dict[str, str]] = {}
    section = None
    for line in text.split("\n"):
        if match := PRESET.fullmatch(line):
            section = found.setdefault(f"[preset.{match[1]}]", {})
        elif line.startswith("["):
            section = None
        elif section is not None:
            key, _, value = line.partition("=")
            if key in KEYS:
                # A name ends at its next = (as the shell check read it); the others are whole.
                section[key] = value.partition("=")[0] if key == "name" else value
    return found


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    errors = []
    reference = None
    web = None
    first_with: dict[str, dict[str, str]] = {}
    found = presets(Path("export_presets.cfg").read_text(encoding="utf-8", newline=""))
    for header, preset in found.items():
        name = preset.get("name", "")
        if "include_filter" not in preset or "exclude_filter" not in preset:
            errors.append(f"preset {header} lacks an include_filter or an exclude_filter")
            continue
        include, exclude = preset["include_filter"], preset["exclude_filter"]
        if not TOOLS_EXCLUDED.fullmatch(exclude):
            errors.append(f"preset {name} has exclude_filter={exclude} without tools/*")
        reference = reference or preset
        if include != reference["include_filter"]:
            errors.append(
                f"preset {name} has include_filter={include}, preset {reference.get('name', '')}"
                f" has {reference['include_filter']}"
            )
        same = first_with.setdefault(preset.get("custom_features", ""), preset)
        if same is not preset and exclude != same["exclude_filter"]:
            errors.append(
                f"preset {name} has exclude_filter={exclude}, preset {same.get('name', '')}"
                f" (same custom_features) has {same['exclude_filter']}"
            )
        if preset.get("platform") == '"Web"':
            web = web or preset
            if preset.get("html/head_include") != web.get("html/head_include"):
                errors.append(
                    f"preset {name} has another html/head_include than preset"
                    f" {web.get('name', '')}: the web presets share their loading page"
                )
    if not found:
        errors.append("it has no preset")
    for message in errors:
        log.error(message, "export_presets.cfg")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
