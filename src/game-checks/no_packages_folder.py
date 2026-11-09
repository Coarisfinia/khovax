"""Fails while the repository has a packages/ folder, or a tracked file names a path in it (#1979):
the folder is src/ now, and a path left behind reads nothing without saying so (#2199, #2203).

    uv run --locked --package khovax-game-checks src/game-checks/no_packages_folder.py
"""

import os
import re
import subprocess
import sys
from pathlib import Path

from game_shared import log
from game_shared.git_files import git_files

# A path in the old folder: a member (game, game-*), or the folder's members in a pattern.
STALE = r"\bpackages/(game|<package>|\*)"


def stale_references() -> list[tuple[str, int]]:
    """Every tracked text file's lines naming the old folder, this file's own included."""
    found = subprocess.run(
        ["git", "grep", "-I", "-n", "-z", "-E", STALE],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    # 1 means no match; anything above is git failing, and reading nothing mustn't pass.
    if found.returncode > 1:
        raise RuntimeError(f"git grep failed: {found.stderr.strip()}")
    fields = re.split("\0|\n", found.stdout)
    return [
        (path, int(line))
        for path, line in zip(fields[0::3], fields[1::3])
        if path and line
    ]


def main() -> int:
    os.chdir(Path(__file__).resolve().parents[2])
    tracked = git_files()
    if not tracked:
        log.error("git lists no tracked files, so there's nothing to check")
        return 1
    failed = False
    moved = [path for path in tracked if path.startswith("packages/")]
    if moved:
        log.error(f"{len(moved)} tracked files are still in packages/: it is src/ now (#1979)")
        failed = True
    for path, line in stale_references():
        log.error("names a path in packages/: it is src/ now (#1979)", path, line)
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
