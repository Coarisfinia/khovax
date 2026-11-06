"""Tests the dev-release step of ci.yml (#1991, #2028) by running it against a stand-in `gh` that
refuses to create the release: a dev build that a newer commit on main has replaced, whose workflows
differ from main's, gives way with a warning, and every other refusal still fails the job. The stand-in plays GitHub, so this needs no network.

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
# REFUSALS of them have been, then AFTER_REFUSALS' error if any. Every call goes to the log the tests
# read.
STAND_IN_GH = r"""#!/usr/bin/env bash
echo "$*" >> "$WORK/calls"
case "$1 $2" in
  "release view") echo "release not found" >&2; exit 1 ;;
  "release create")
    count=$(grep -c "^release create" "$WORK/calls")
    if [ "$count" -le "$REFUSALS" ]; then echo "$CREATE_ERROR" >&2; exit 1; fi
    if [ -n "$AFTER_REFUSALS" ]; then echo "$AFTER_REFUSALS" >&2; exit 1; fi ;;
  "api repos/owner/repo/commits/main")
    if [ -n "$HEAD_ERROR" ]; then echo "$HEAD_ERROR" >&2; exit 1; fi
    echo "$MAIN_HEAD" ;;
  "api repos/owner/repo/compare/$GITHUB_SHA...$MAIN_HEAD") echo "$STATUS" ;;
  "api repos/owner/repo/contents/.github?ref=$GITHUB_SHA") echo "$OWN_WORKFLOWS" ;;
  "api repos/owner/repo/contents/.github?ref=$MAIN_HEAD") echo "$MAIN_WORKFLOWS" ;;
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
    def run_step(
        self,
        tag="v0.1.0-dev.1",
        refusals=99,
        main_head=NEWER,
        error=REFUSED,
        after_refusals="",
        head_error="",
        status="ahead",
        own_workflows="tree1",
        main_workflows="tree2",
    ):
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
                    "AFTER_REFUSALS": after_refusals,
                    "HEAD_ERROR": head_error,
                    "STATUS": status,
                    "OWN_WORKFLOWS": own_workflows,
                    "MAIN_WORKFLOWS": main_workflows,
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

    def test_a_replaced_dev_build_whose_workflows_differ_from_mains_gives_way(self):
        """Whether or not the commit changed a workflow itself: #2028's changed none."""
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

    def assert_refused_and_failed(self, done, calls):
        """It failed at the refusal after all its tries, not on something earlier in the script."""
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release create")), 4)
        self.assertEqual(self.calls(calls, "release upload"), [])
        self.assertNotIn("GitHub refused to create", done.stdout + done.stderr)

    def test_a_refusal_of_the_newest_commit_fails(self):
        done, calls = self.run_step(main_head=SHA)
        self.assert_refused_and_failed(done, calls)
        self.assertEqual(len(self.calls(calls, "api repos/owner/repo/commits/main")), 1)

    def test_a_refusal_while_mains_workflows_match_the_commits_fails(self):
        done, calls = self.run_step(main_workflows="tree1")
        self.assert_refused_and_failed(done, calls)

    def test_a_refusal_of_a_commit_main_isnt_past_fails(self):
        done, calls = self.run_step(status="diverged")
        self.assert_refused_and_failed(done, calls)

    def test_an_empty_comparison_with_main_fails(self):
        done, calls = self.run_step(status="")
        self.assert_refused_and_failed(done, calls)

    def test_no_workflows_folder_to_compare_fails(self):
        done, calls = self.run_step(own_workflows="", main_workflows="")
        self.assert_refused_and_failed(done, calls)

    def test_a_refused_nightly_fails_because_nothing_replaces_it_today(self):
        done, calls = self.run_step(tag="v0.1.0-nightly.20261102")
        self.assert_refused_and_failed(done, calls)
        self.assertEqual(self.calls(calls, "api repos/owner/repo/commits/main"), [])

    def test_a_failed_look_at_main_fails(self):
        done, calls = self.run_step(head_error="HTTP 404: Not Found")
        self.assert_refused_and_failed(done, calls)

    def test_an_empty_answer_about_main_fails(self):
        done, calls = self.run_step(main_head="")
        self.assert_refused_and_failed(done, calls)

    def test_a_refusal_then_another_error_fails(self):
        done, calls = self.run_step(refusals=1, after_refusals="HTTP 422: Validation Failed")
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release create")), 2)

    def test_any_other_error_fails_at_once(self):
        done, calls = self.run_step(error="HTTP 422: Validation Failed")
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release create")), 1)


if __name__ == "__main__":
    unittest.main()
