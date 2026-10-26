"""Checks the rule change files (#736) and the save formats' change files (#801, every
format_changes/ folder): each file's name and frontmatter, and that the folders are append-only
(#876): a rule change file deleted or renamed would give the rules (RulesChanges, a digest of the
names of the files in core/rules_changes/) an id that older rules may already have had, and saves
name their format changes (FormatChanges), so a build without one could no longer read them.
Whether a change needs a new rule change file is the rules-compare job's
(packages/game-replays/rules_compare.py).
<base> is the commit the change is compared with, e.g. HEAD^1 of a pull request's merge commit.

    uv run --locked --package khovax-game-checks packages/game-checks/rules_changes_check.py <base>
"""

import os
import posixpath
import re
import subprocess
import sys
from pathlib import Path

from game_shared import log

FOLDER = "core/rules_changes"
# Each save format's changes are in a folder of this name, next to its reader.
FORMATS = "format_changes"
NAME = re.compile(r"([0-9]+)-[a-z0-9-]+\.md")


def is_change(path: str) -> bool:
    """Whether the path, relative to the game's folder, is in a folder of change files."""
    folder = posixpath.dirname(path)
    return folder == FOLDER or posixpath.basename(folder) == FORMATS


def names(commit: str) -> set[str] | None:
    """The change files' paths at that commit, relative to the game's folder, or None when git
    can't list them. The folder is the game's: under packages/game, or at the root in a commit from
    before the move there (#1101), so the commit that moves it compares names, not paths."""
    game = "packages/game" if git("cat-file", "-e", f"{commit}:packages/game/project.godot") else ""
    listing = subprocess.run(
        ["git", "ls-tree", "-r", "-z", "--full-tree", "--name-only", f"{commit}:{game}"],
        stdout=subprocess.PIPE,
        text=True,
    )
    if listing.returncode != 0:
        return None
    return {path for path in listing.stdout.split("\0") if path and is_change(path)}


def git(*args: str) -> bool:
    """Whether the git command succeeds, its output dropped."""
    return subprocess.run(("git", *args), capture_output=True).returncode == 0


def deleted_since(base: str) -> list[str] | None:
    """The change files that HEAD no longer has since base, or None when git can't compare them.
    A renamed file shows as deleted (and another added)."""
    before, after = names(base), names("HEAD")
    if before is None or after is None:
        return None
    return sorted(before - after)


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    base = sys.argv[1]
    failed = False

    folders = [FOLDER, *sorted(str(path) for path in Path(".").glob(f"**/{FORMATS}"))]
    files = [
        f"{folder}/{entry}"
        for folder in folders
        for entry in sorted(os.listdir(folder))
        if not entry.startswith(".")
    ]
    for file in files:
        name = NAME.fullmatch(posixpath.basename(file))
        if not name:
            log.error("a change file is named <issue>-<slug>.md", file)
            failed = True
            continue
        # newline="": a carriage return stays, so a CRLF frontmatter fails as it did in the shell.
        text = Path(file).read_text(encoding="utf-8", newline="")
        lines = text.split("\n")
        # No pr (#758): the squash commit that added the file names it (git log --diff-filter=A).
        if lines[0:3:2] != ["---", "---"] or lines[1:2] != [f"issue: {name[1]}"]:
            log.error(
                "its frontmatter is its issue (the file's number), nothing else (no pr: git log"
                " finds it)",
                file,
            )
            failed = True
        if re.search(r"/pull/[0-9]", text):
            log.error("it links its issue, not its pull request (git log finds that)", file)
            failed = True

    deleted = deleted_since(base)
    if deleted is None:
        log.error(f"git can't compare the change files with {base}")
        return 1
    for path in deleted:
        log.error("a change file is never deleted or renamed: its folder is append-only", path)
        failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
