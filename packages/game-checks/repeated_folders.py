"""Fails when a tracked path repeats a folder name (#442): slices/tiles/data/tiles/ is refused,
slices/tiles/data/foo/ is fine. Only folders count, not the file's own name. The paths are the
game's, from its project folder (#1101), whose own packages/game/game/ isn't a repeat.

    uv run --locked packages/game-checks/repeated_folders.py
"""

import os
import sys
from pathlib import Path

from annotations import error
from git_files import git_files


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    repeated = [
        path for path in git_files() if len(set(folders := path.split("/")[:-1])) < len(folders)
    ]
    for path in repeated:
        print(error(path, "its path repeats a folder name"))
    return 1 if repeated else 0


if __name__ == "__main__":
    sys.exit(main())
