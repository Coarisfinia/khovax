"""Tests the always-user-facing files of approve-cleared.yml's guard (#1874, #2061, #2111) by
running its check step against a stand-in `gh` that answers with a pull request's changed files:
the guard refuses a change to the game's assets, texts and world, and to every resource pack, and
lets the rest through to the review subagent's call. The stand-in plays GitHub, so this needs no
network.

    uv run --locked --package khovax-game-checks packages/game-checks/test_approve_cleared.py
"""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/approve-cleared.yml"
STEP = "Check that the agent bot or the owner cleared it"
BOT = "coarisfinia-ai-agent[bot]"
HEAD = "a" * 40

# The pull request at HEAD into main, its changed files as the guard's own --jq would print them,
# and no changed workflow.
STAND_IN_GH = r"""#!/usr/bin/env bash
case "$*" in
  "api repos/owner/repo/pulls/7 "*) echo "$HEAD main" ;;
  *"compare/main...$HEAD"*"workflows"*) ;;
  *"compare/main...$HEAD"*) cat "$WORK/files" ;;
  *) echo "unexpected: gh $*" >&2; exit 1 ;;
esac
"""


def step_script() -> str:
    """The step's own script, as the workflow has it, so the test can't drift from what runs."""
    lines = WORKFLOW.read_text(encoding="utf-8").splitlines()
    start = next(i for i, line in enumerate(lines) if STEP in line)
    start = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |") + 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    body = []
    for line in lines[start:]:
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            break
        body.append(line)
    return textwrap.dedent("\n".join(body)) + "\n"


class ApproveClearedTest(unittest.TestCase):
    def check(self, *changes: tuple[str, str | None]) -> tuple[bool, str]:
        """Runs the check on files changed as (path, renamed from); True if it would approve."""
        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            (work / "bin").mkdir()
            (work / "bin/gh").write_text(STAND_IN_GH, encoding="utf-8")
            (work / "bin/gh").chmod(0o755)
            lines = []
            for path, previous in changes:
                lines.append("F" + json.dumps(path))
                if previous:
                    lines.append("P" + json.dumps(previous))
            (work / "files").write_text("\n".join(lines) + "\n", encoding="utf-8")
            (work / "output").touch()
            done = subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-c", step_script()],
                cwd=work,
                env={
                    **os.environ,
                    "PATH": f"{work / 'bin'}{os.pathsep}{os.environ['PATH']}",
                    "WORK": str(work),
                    "REPO": "owner/repo",
                    "PR": "7",
                    "HEAD": HEAD,
                    "DEFAULT_BRANCH": "main",
                    "SENDER": BOT,
                    "SENDER_TYPE": "Bot",
                    "BOT": BOT,
                    "CHANGED_FILES": str(len(changes)),
                    "RUNNER_TEMP": str(work),
                    "GITHUB_OUTPUT": str(work / "output"),
                },
                capture_output=True,
                text=True,
                check=False,
            )
            log = done.stdout + done.stderr
            self.assertEqual(done.returncode, 0, log)
            approved = "sender=" in (work / "output").read_text(encoding="utf-8")
            return approved, log

    def assert_refused(self, *changes: tuple[str, str | None]) -> None:
        approved, log = self.check(*changes)
        self.assertFalse(approved, log)
        self.assertIn("always user-facing", log)

    def test_tooling_may_be_approved(self):
        approved, log = self.check(("packages/game-checks/some_check.py", None))
        self.assertTrue(approved, log)

    def test_the_games_world_is_refused(self):
        self.assert_refused(("packages/game/realms/ardvaun.md", None))

    def test_a_resource_packs_file_is_refused(self):
        self.assert_refused(("resourcepacks/default/realms/ardvaun.md", None))

    def test_a_rename_out_of_a_resource_pack_is_refused(self):
        self.assert_refused(
            ("packages/game-checks/ardvaun.md", "resourcepacks/default/realms/ardvaun.md")
        )


if __name__ == "__main__":
    unittest.main()
