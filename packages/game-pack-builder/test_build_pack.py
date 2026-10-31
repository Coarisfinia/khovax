"""Tests build_pack.py's run() (#1974) against a stand-in for Godot: a run that exits fine but
reports, as Godot does at exit, objects it leaked fails the build, like one reporting an error; a
clean run passes. Godot names leaked objects only in a warning once it exits, which the builder's
callers never see, since it keeps Godot's output to itself unless the run fails.

    uv run --locked --package khovax-game-pack-builder packages/game-pack-builder/test_build_pack.py
"""

import stat
import sys
import tempfile
import unittest
from pathlib import Path

from build_pack import run

# What Godot 4.7 prints at exit when objects outlive it (#1906, #1955).
LEAKED = "WARNING: 1 ObjectDB instance was leaked at exit (run with `--verbose` for details)."


def stand_in(folder: Path, output: str) -> str:
    """An executable at `folder` that prints `output` on stderr and exits with 0, as Godot does."""
    editor = folder / "godot"
    editor.write_text(f"#!{sys.executable}\nimport sys\nsys.stderr.write({output!r})\n", encoding="utf-8")
    editor.chmod(editor.stat().st_mode | stat.S_IXUSR)
    return str(editor)


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = Path(tempfile.mkdtemp())

    def test_a_clean_run_passes(self) -> None:
        run(stand_in(self.folder, "Godot Engine v4.7.2.stable\n"), self.folder, "--import")

    def test_a_leak_at_exit_fails(self) -> None:
        with self.assertRaises(RuntimeError):
            run(stand_in(self.folder, f"Godot Engine v4.7.2.stable\n{LEAKED}\n"), self.folder, "--import")

    def test_an_error_fails(self) -> None:
        with self.assertRaises(RuntimeError):
            run(stand_in(self.folder, "ERROR: 2 resources still in use at exit.\n"), self.folder, "--import")


if __name__ == "__main__":
    unittest.main()
