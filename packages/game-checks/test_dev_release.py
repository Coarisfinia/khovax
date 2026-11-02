"""Tests the dev-release step of ci.yml (#1991) by running it against a stand-in `gh` that refuses
to create the release: a dev build a newer commit on main has replaced gives way with a warning, and
every other refusal still fails the job. The stand-in plays GitHub, so this needs no network.

    uv run --locked --package khovax-game-checks packages/game-checks/test_dev_release.py
"""

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

CI = Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml"
STEP = "Create the dev or nightly release"
REFUSED = "HTTP 403: Resource not accessible by integration (https://api.github.com/releases)"
SHA = "a" * 40
NEWER = "b" * 40

# Answers as GitHub did in the failed run: no release of this tag yet, and each create refused until
# REFUSALS of them have been. Every call goes to the log the tests read.
STAND_IN_GH = r"""#!/usr/bin/env bash
echo "$*" >> "$WORK/calls"
case "$1 $2" in
  "release view") echo "release not found" >&2; exit 1 ;;
  "release create")
    count=$(grep -c "^release create" "$WORK/calls")
    if [ "$count" -le "$REFUSALS" ]; then echo "$CREATE_ERROR" >&2; exit 1; fi ;;
  "api repos/owner/repo/commits/main") echo "$MAIN_HEAD" ;;
esac
"""


def step_script() -> str:
    """The step's own script, as ci.yml has it, so the test can't drift from what CI runs."""
    lines = CI.read_text(encoding="utf-8").splitlines()
    start = next(i for i, line in enumerate(lines) if STEP in line)
    start = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: |") + 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    body = []
    for line in lines[start:]:
        if line.strip() and len(line) - len(line.lstrip()) < indent:
            break
        body.append(line)
    return textwrap.dedent("\n".join(body)) + "\n"


class DevReleaseTest(unittest.TestCase):
    def run_step(self, tag="v0.1.0-dev.1", refusals=99, main_head=NEWER, error=REFUSED):
        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            stand_ins = work / "bin"
            stand_ins.mkdir()
            for name, script in (("gh", STAND_IN_GH), ("sleep", "#!/bin/sh\n")):
                (stand_ins / name).write_text(script, encoding="utf-8")
                (stand_ins / name).chmod(0o755)
            project = work / "packages/game/project.godot"
            project.parent.mkdir(parents=True)
            project.write_text('[application]\nconfig/name="Khovax"\n', encoding="utf-8")
            for build in (
                "khovax-debug-apk/khovax.apk",
                "khovax-windows/khovax.exe",
                "khovax-linux/khovax.x86_64",
                "khovax-web/index.html",
            ):
                (work / "builds" / build).parent.mkdir(parents=True)
                (work / "builds" / build).touch()
            (work / "calls").touch()
            done = subprocess.run(
                ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", step_script()],
                cwd=work,
                env={
                    **os.environ,
                    "PATH": f"{stand_ins}{os.pathsep}{os.environ['PATH']}",
                    "WORK": str(work),
                    "REFUSALS": str(refusals),
                    "CREATE_ERROR": error,
                    "MAIN_HEAD": main_head,
                    "TAG": tag,
                    "RUNNER_TEMP": str(work),
                    "GITHUB_REPOSITORY": "owner/repo",
                    "GITHUB_REPOSITORY_OWNER": "owner",
                    "GITHUB_SHA": SHA,
                    "GITHUB_SERVER_URL": "https://github.com",
                    "GITHUB_RUN_ID": "1",
                },
                capture_output=True,
                text=True,
                check=False,
            )
            return done, (work / "calls").read_text(encoding="utf-8").splitlines()

    def calls(self, calls, start):
        return [call for call in calls if call.startswith(start)]

    def test_a_replaced_dev_build_gives_way_with_a_warning(self):
        done, calls = self.run_step()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("::warning::", done.stderr + done.stdout)
        self.assertIn(NEWER, done.stderr + done.stdout)
        self.assertEqual(len(self.calls(calls, "release create")), 4)
        self.assertEqual(self.calls(calls, "release upload"), [])
        self.assertEqual(self.calls(calls, "release edit"), [])

    def test_a_refusal_that_passes_still_publishes(self):
        done, calls = self.run_step(refusals=2)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release create")), 3)
        self.assertEqual(len(self.calls(calls, "release upload")), 4)
        self.assertEqual(len(self.calls(calls, "release edit")), 1)

    def test_a_refusal_of_the_newest_commit_fails(self):
        done, calls = self.run_step(main_head=SHA)
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.calls(calls, "release edit"), [])

    def test_a_refused_nightly_fails_because_nothing_replaces_it_today(self):
        done, _ = self.run_step(tag="v0.1.0-nightly.20261102")
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_any_other_error_fails_at_once(self):
        done, calls = self.run_step(error="HTTP 422: Validation Failed")
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release create")), 1)


if __name__ == "__main__":
    unittest.main()
