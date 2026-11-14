"""The one way the game's tools report (#1115): in CI as GitHub's workflow commands, which turn a
notice, a warning or an error into an annotation, and elsewhere as plain lines.

An annotation names its file from the repository's root, the only path GitHub links into a pull
request's diff (#1106), while the tools name files from their working directory (most run in the
game's folder, src/game): `text` turns one into the other, locally too, so the lines read the
same everywhere.
"""

import os
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Literal

Level = Literal["info", "notice", "warning", "error"]

ROOT = Path(__file__).resolve().parents[3]


def text(level: Level, message: str, file: str | None = None, line: int | None = None) -> str:
    """The line that reports the message, on a file named from the working directory and a line
    of it when they're given. An info names no file: it is a plain line in CI too."""
    if level == "info":
        return message
    path = None if file is None else _from_root(file)
    if os.environ.get("GITHUB_ACTIONS") != "true":
        where = "" if path is None else f"{path}: " if line is None else f"{path}:{line}: "
        return f"{where}{level}: {message}"
    where = "" if path is None else f" file={path}" if line is None else f" file={path},line={line}"
    # A workflow command ends at its line, so line breaks in the message are escaped (and so is %).
    escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return f"::{level}{where}::{escaped}"


def info(message: str) -> None:
    print(text("info", message))


def notice(message: str, file: str | None = None, line: int | None = None) -> None:
    print(text("notice", message, file, line))


def warning(message: str, file: str | None = None, line: int | None = None) -> None:
    print(text("warning", message, file, line))


def error(message: str, file: str | None = None, line: int | None = None) -> None:
    print(text("error", message, file, line))


@contextmanager
def group(title: str) -> Iterator[None]:
    """Folds what is printed inside it under `title` in CI's log; elsewhere `title` is a plain
    heading line. Flushed, since a subprocess inside it writes to the same log straight away."""
    in_ci = os.environ.get("GITHUB_ACTIONS") == "true"
    print(f"::group::{title}" if in_ci else f"--- {title}", flush=True)
    try:
        yield
    finally:
        if in_ci:
            print("::endgroup::", flush=True)


def _from_root(file: str) -> str:
    return Path(os.path.relpath(Path.cwd() / file, ROOT)).as_posix()
