"""Fails when a tracked path repeats a folder name (#442): slices/tiles/data/tiles/ is refused,
slices/tiles/data/foo/ is fine. Only folders count, not the file's own name.

    uv run --locked tools/checks/repeated_folders.py
"""

import os
import sys
from pathlib import Path

from git_files import git_files


def main() -> int:
    os.chdir(Path(__file__).resolve().parents[2])
    repeated = [
        path for path in git_files() if len(set(folders := path.split("/")[:-1])) < len(folders)
    ]
    for path in repeated:
        print(f"::error file={path}::its path repeats a folder name")
    return 1 if repeated else 0


if __name__ == "__main__":
    sys.exit(main())
