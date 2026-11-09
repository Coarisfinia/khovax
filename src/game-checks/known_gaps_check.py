"""Checks that the territory quests' known-gap list only shrinks (#2182): KNOWN_GAPS in
tests/e2e/territory_quests.gd names the faction and territory pairs without a quest yet (#639), and
a change may take entries out, never add one. The content flow refuses an entry whose quest exists;
it can't see an entry added to get past a new faction or territory, which this does.
<base> is the commit the change is compared with, e.g. HEAD^1 of a pull request's merge commit.

    uv run --locked --package khovax-game-checks src/game-checks/known_gaps_check.py <base>
"""

import re
import subprocess
import sys

from game_shared import log

FILE = "game/tests/e2e/territory_quests.gd"
# The folder the game lies in: src/, or packages/ before the rename (#1979).
TOPS = ("src", "packages")
# A string or a comment, read in one pass so that neither is taken for the other.
TOKEN = re.compile(r"""\"[^"\n]*"|'[^'\n]*'|#[^\n]*""")
# The list, whose brackets only count outside its strings, and whose ] ends its line.
LIST = re.compile(
    r"""^const KNOWN_GAPS: Array\[String\] = \[((?:"[^"\n]*"|'[^'\n]*'|[^\]"'])*)\][ \t]*$""",
    re.MULTILINE,
)
# GDScript writes a string in either quote.
ENTRY = re.compile(r"""(["'])(.*?)\1""")


def uncommented(text: str) -> str:
    """The text without its comments, its strings as they were."""
    return TOKEN.sub(lambda token: "" if token[0].startswith("#") else token[0], text)


def entries(text: str) -> set[str] | None:
    """The list's entries in a version of the file, or None when the file has no list that can be
    read: a list followed by anything else on the line of its ] can't be."""
    found = LIST.search(uncommented(text))
    if found is None:
        return None
    return {entry[2] for entry in ENTRY.finditer(found[1])}


def added(before: str, after: str) -> list[str] | None:
    """The entries `after` has that `before` hasn't, sorted, or None when either has no list."""
    old, new = entries(before), entries(after)
    return None if old is None or new is None else sorted(new - old)


def version(commit: str) -> str | None:
    """The file's text at that commit, or None when git can't show it."""
    for top in TOPS:
        shown = subprocess.run(
            ["git", "show", f"{commit}:{top}/{FILE}"], capture_output=True, text=True, encoding="utf-8"
        )
        if shown.returncode == 0:
            return shown.stdout
    return None


def main() -> int:
    base = sys.argv[1]
    before, after = version(base), version("HEAD")
    new = None if before is None or after is None else added(before, after)
    if new is None:
        log.error(f"git can't compare KNOWN_GAPS with {base}", FILE)
        return 1
    for entry in new:
        log.error(f"{entry} is new in KNOWN_GAPS, which only shrinks: write its quest", FILE)
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
