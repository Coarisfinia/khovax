"""Tests that a checkout without the resource packs' link (packages/game/resourcepacks, made by
packages/game-build/link_resource_packs.py, #1978) fails fast and says so once, naming the link and
the command that makes it (#2123), rather than looping on script errors until it's killed. The game
runs from a copy of the project made of links to its files, the resource packs' link left out, so
the checkout itself is never touched: the main scene, as the game boots, and two tools run with
-s, the load test and the in-game model render that render_media.py runs (#2131), as the headless
tools start.

    [GODOT=<binary>] uv run --locked --package khovax-game-checks \\
        packages/game-checks/test_missing_pack_link.py

GODOT defaults to `godot`. The project must have been imported (`godot --headless --import`).
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

GAME = Path(__file__).resolve().parents[1] / "game"
LINK = "resourcepacks"
# Left out too: a local export copies the built default pack in here, and a run with one never
# needs the link.
BUILT = "packs"
# What the message names: the link script, which says how to run it.
NAMED = "link_resource_packs.py"
# A run that names the missing link stops within this; one that loops runs until it's killed.
TIMEOUT_SECONDS = 60


def run_without_link(*arguments: str) -> tuple[int | None, str]:
    """Godot's exit code (None when it timed out) and output, run headless on a copy of the project
    without the resource packs' link."""
    godot = os.environ.get("GODOT", "godot")
    with tempfile.TemporaryDirectory() as folder:
        project = Path(folder)
        for entry in GAME.iterdir():
            if entry.name not in (LINK, BUILT):
                (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        try:
            done = subprocess.run(
                [godot, "--headless", "--path", str(project), *arguments],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=TIMEOUT_SECONDS,
                check=False,
            )
        except subprocess.TimeoutExpired as late:
            return None, (late.output or b"").decode("utf-8", "replace")
        return done.returncode, done.stdout.decode("utf-8", "replace")


class MissingPackLinkTest(unittest.TestCase):
    def assert_fails_naming_link(self, *arguments: str) -> None:
        code, output = run_without_link(*arguments)
        tail = output[-4000:]
        self.assertIsNotNone(code, f"still running after {TIMEOUT_SECONDS} s:\n{tail}")
        self.assertNotEqual(code, 0, f"exited with 0:\n{tail}")
        self.assertEqual(output.count(NAMED), 1, f"doesn't name {NAMED} once:\n{tail}")

    def test_main_scene(self) -> None:
        self.assert_fails_naming_link()

    def test_tool(self) -> None:
        self.assert_fails_naming_link("-s", "res://tools/godot/load_test.gd", "--", "ticks=10")

    def test_model_render(self) -> None:
        model = next(iter(sorted(GAME.glob("assets/*/*.glb"))))
        with tempfile.TemporaryDirectory() as out:
            self.assert_fails_naming_link(
                "-s", "res://tools/models/render_in_game.gd", "--",
                "res://" + model.relative_to(GAME).as_posix(), out, "--seed=0",
            )


if __name__ == "__main__":
    unittest.main()
