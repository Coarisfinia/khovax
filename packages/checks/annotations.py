"""GitHub's error annotations, which name their file from the repository's root (#1106)."""

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def error(file: str, message: str, line: int | None = None) -> str:
    """An error annotation on a file named from the working directory, as the checks read it.

    GitHub links an annotation into the pull request's diff only by the file's path from the
    repository's root, and most checks run in the game's folder (packages/game).
    """
    path = Path(os.path.relpath(Path.cwd() / file, ROOT)).as_posix()
    where = f"file={path}" if line is None else f"file={path},line={line}"
    return f"::error {where}::{message}"
