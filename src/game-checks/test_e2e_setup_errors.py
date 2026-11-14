"""Tests that the headless e2e runner (src/game/tests/e2e/run_e2e.gd) fails when an error is logged
during its own setup, before the first flow runs (#2367): the setup reads all the content ahead, and
an error there is logged once and cached, so no flow would see it again. The runner runs on a copy of
the project made of links to its files, with one species file broken and a single flow that always
passes, so the checkout itself is never touched.

    [GODOT=<binary>] uv run --locked --package khovax-game-checks \\
        src/game-checks/test_e2e_setup_errors.py

GODOT defaults to `godot`. The project must have been imported (`godot --headless --import`) and
linked to the resource packs (`src/game-build/link_resource_packs.py`).
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

GAME = Path(__file__).resolve().parents[1] / "game"
ROOT = GAME.parents[1]
FLOWS = Path("tests") / "e2e"
PACK = Path("resourcepacks") / "default"
BROKEN_KIND = "species"
# The only flow in the copy: it passes, so only the setup can fail the run.
PASSING_FLOW = 'extends RefCounted\n\n\nfunc run(_tree: SceneTree) -> String:\n\treturn ""\n'
TIMEOUT_SECONDS = 120


def link_all(source: Path, target: Path, *keep_out: str) -> None:
    """Makes `target` a folder of links to the entries of `source`, leaving out `keep_out`."""
    target.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        if entry.name not in keep_out:
            (target / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())


def run_with_broken_content() -> tuple[int | None, str]:
    """The runner's exit code (None when it timed out) and output, on a copy of the project whose
    only flow passes and whose first species file is broken."""
    godot = os.environ.get("GODOT", "godot")
    broken = sorted((ROOT / PACK / BROKEN_KIND).glob("*.jsonc"))[0].name
    with tempfile.TemporaryDirectory() as folder:
        project = Path(folder)
        link_all(GAME, project, "tests", "resourcepacks")
        link_all(GAME / "tests", project / "tests", "e2e")
        flows = project / FLOWS
        link_all(GAME / FLOWS, flows)
        for flow in flows.glob("test_*"):
            flow.unlink()
        (flows / "test_passing.gd").write_text(PASSING_FLOW, encoding="utf-8")
        link_all(ROOT / PACK, project / PACK, BROKEN_KIND)
        link_all(ROOT / PACK / BROKEN_KIND, project / PACK / BROKEN_KIND, broken)
        (project / PACK / BROKEN_KIND / broken).write_text('{ "id": ', encoding="utf-8")
        try:
            done = subprocess.run(
                [godot, "--headless", "--path", str(project),
                 "-s", "res://tests/e2e/run_e2e.gd", "--", "--seed=0"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=TIMEOUT_SECONDS,
                check=False,
            )
        except subprocess.TimeoutExpired as late:
            return None, (late.output or b"").decode("utf-8", "replace")
        return done.returncode, done.stdout.decode("utf-8", "replace")


class E2eSetupErrorsTest(unittest.TestCase):
    def test_setup_error_fails_the_run(self) -> None:
        code, output = run_with_broken_content()
        tail = output[-4000:]
        self.assertIsNotNone(code, f"still running after {TIMEOUT_SECONDS} s:\n{tail}")
        self.assertIn("PASS  test_passing.gd", output, f"the passing flow didn't run:\n{tail}")
        self.assertIn("FAIL  setup", output, f"the setup's error isn't reported:\n{tail}")
        self.assertNotEqual(code, 0, f"exited with 0:\n{tail}")


if __name__ == "__main__":
    unittest.main()
