"""Fails on a tr() literal with two or more % placeholders (#1704): % fills its values in order, so
a translation couldn't put them in another one. Such a text names its values instead, filled with
format(): tr("Carried {place}: {monster}").format({"place": place, "monster": shown}), which a
language may reorder freely. A text with one value may keep its %.

It reads the literals translations_pot.py extracts, from the same scripts, the plurals of tr_n()
included.

    uv run --locked --package khovax-game-checks packages/game-checks/tr_placeholders.py
"""

import os
import re
import sys
from collections.abc import Iterator
from pathlib import Path

from game_shared import log
from game_shared.git_files import git_files
from translations_pot import script_texts

# A Godot format specifier (String's % operator): its flags (u for unsigned), its value's index
# (1$), width and precision (a bare "." or a "*" among them), then its conversion; or %%, a percent
# sign, read first so "%%s" holds no value.
SPECIFIER = re.compile(r"%%|%[-+u0-9$.*]*[scdoxXfv]")
# An indexed specifier's value, counted from 1.
INDEX = re.compile(r"(?<![0-9])0*([1-9][0-9]*)\$")


def placeholders(text: str) -> int:
    """How many values the text's % fills, read left to right as Godot does: a specifier takes the
    next value, and one more for each * in it, which takes its width or precision from the values
    too; an indexed one (%2$s) takes the value it names, a * after its index included, so a repeated
    index fills one value."""
    used: set[int] = set()
    following = 0
    for match in SPECIFIER.findall(text):
        if match == "%%":
            continue
        indexed = INDEX.search(match)
        # A * before the index makes the index hang on the width's value at run time (a negative
        # one keeps it from selecting), so such a specifier counts as unindexed: every value in it.
        if indexed is not None and "*" not in match[: indexed.start()]:
            used.add(int(indexed[1]) - 1)
            continue
        taken = 1 + match.count("*")
        used.update(range(following, following + taken))
        following += taken
    return len(used)


def crowded(source: str) -> Iterator[str]:
    """The script's tr() literals (texts and plurals) with two or more % placeholders."""
    for found in script_texts(source):
        for text in (found.text, found.plural):
            if text is not None and placeholders(text) >= 2:
                yield text


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    failed = False
    for path in sorted(git_files("*.gd")):
        # The tools and tests are never shown to a player.
        if path.startswith(("tools/", "tests/")):
            continue
        for text in crowded(Path(path).read_text(encoding="utf-8")):
            log.error(
                f"{text!r} fills two or more values with %, in their order: name them,"
                ' tr("{a} … {b}").format({"a": …, "b": …}), so a translation can reorder them'
                " (README, Translations)",
                path,
            )
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
