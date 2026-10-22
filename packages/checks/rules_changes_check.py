"""Checks the rule change files (#736): each file's name and frontmatter, and that the folder is
append-only (#876): a file deleted or renamed would give the rules (RulesChanges, a digest of the
names of the files in core/rules_changes/) an id that older rules may already have had. Whether a
change needs a new file is the rules-compare job's (packages/replays/rules_compare.py).
<base> is the commit the change is compared with, e.g. HEAD^1 of a pull request's merge commit.

    uv run --locked packages/checks/rules_changes_check.py <base>
"""

import os
import re
import subprocess
import sys
from pathlib import Path

from annotations import error

FOLDER = "core/rules_changes"
NAME = re.compile(r"([0-9]+)-[a-z0-9-]+\.md")


def names(commit: str) -> set[str] | None:
    """The file names in FOLDER at that commit, or None when git can't list them. The folder is the
    game's: under packages/game, or at the root in a commit from before the move there (#1101), so
    the commit that moves it compares names, not paths."""
    game = "packages/game/" if git("cat-file", "-e", f"{commit}:packages/game/project.godot") else ""
    listing = subprocess.run(
        ["git", "ls-tree", "-z", "--full-tree", "--name-only", f"{commit}:{game}{FOLDER}"],
        stdout=subprocess.PIPE,
        text=True,
    )
    if listing.returncode != 0:
        return None
    return {name for name in listing.stdout.split("\0") if name}


def git(*args: str) -> bool:
    """Whether the git command succeeds, its output dropped."""
    return subprocess.run(("git", *args), capture_output=True).returncode == 0


def deleted_since(base: str) -> list[str] | None:
    """The files under FOLDER that HEAD no longer has since base, or None when git can't compare
    them. A renamed file shows as deleted (and another added)."""
    before, after = names(base), names("HEAD")
    if before is None or after is None:
        return None
    return [f"{FOLDER}/{name}" for name in sorted(before - after)]


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    base = sys.argv[1]
    failed = False

    for entry in sorted(path for path in os.listdir(FOLDER) if not path.startswith(".")):
        file = f"{FOLDER}/{entry}"
        name = NAME.fullmatch(entry)
        if not name:
            print(error(file, "a rule change file is named <issue>-<slug>.md"))
            failed = True
            continue
        # newline="": a carriage return stays, so a CRLF frontmatter fails as it did in the shell.
        text = Path(file).read_text(encoding="utf-8", newline="")
        lines = text.split("\n")
        # No pr (#758): the squash commit that added the file names it (git log --diff-filter=A).
        if lines[0:3:2] != ["---", "---"] or lines[1:2] != [f"issue: {name[1]}"]:
            print(
                error(
                    file,
                    "its frontmatter is its issue (the file's number), nothing else (no pr: git"
                    " log finds it)",
                )
            )
            failed = True
        if re.search(r"/pull/[0-9]", text):
            print(error(file, "it links its issue, not its pull request (git log finds that)"))
            failed = True

    deleted = deleted_since(base)
    if deleted is None:
        print(f"::error::git can't compare {FOLDER} with {base}")
        return 1
    for path in deleted:
        print(
            error(path, "a rule change file is never deleted or renamed: the folder is append-only")
        )
        failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
