"""Tests the dev-release step of ci.yml (#1991, #2028) by running it against a stand-in `gh` that
refuses to create the release: a dev build that a newer commit on main has replaced, whose workflows
differ from main's, gives way with a warning, and every other refusal still fails the job. An
upload that fails for good drops the draft it was filling, and a published release sweeps away dev
drafts older than a day, and nothing else (#2024). The stand-in plays GitHub, so this needs no
network.

    uv run --locked --package khovax-game-checks packages/game-checks/test_dev_release.py
"""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

CI = Path(__file__).resolve().parents[2] / ".github/workflows/ci.yml"
STEP = "Create the dev or nightly release"
REFUSED = "HTTP 403: Resource not accessible by integration (https://api.github.com/releases)"
SHA = "a" * 40
NEWER = "b" * 40

# Answers as GitHub did in the failed run: no release of this tag yet, and each create refused until
# REFUSALS of them have been, then AFTER_REFUSALS' error if any. The releases list is releases.json:
# a create that passes adds draft 7 of TAG, publishing it makes it a release, a delete removes one
# (or fails with DELETE_ERROR), and a list runs the call's own --jq filter over it, so the step's
# filters are tested as written. The list fails with LIST_ERROR and an upload with UPLOAD_ERROR if
# they are set. Every call goes to the log the tests read.
STAND_IN_GH = r"""#!/usr/bin/env bash
echo "$*" >> "$WORK/calls"
case "$1 $2" in
  "release view") echo "release not found" >&2; exit 1 ;;
  "release create")
    count=$(grep -c "^release create" "$WORK/calls")
    if [ "$count" -le "$REFUSALS" ]; then echo "$CREATE_ERROR" >&2; exit 1; fi
    if [ -n "$AFTER_REFUSALS" ]; then echo "$AFTER_REFUSALS" >&2; exit 1; fi
    jq --arg tag "$TAG" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '. + [{id: 7, tag_name: $tag, draft: true, created_at: $now}]' "$WORK/releases.json" > "$WORK/next"
    mv "$WORK/next" "$WORK/releases.json" ;;
  "release upload") if [ -n "$UPLOAD_ERROR" ]; then echo "$UPLOAD_ERROR" >&2; exit 1; fi ;;
  "release edit")
    jq 'map(if .id == 7 then .draft = false else . end)' "$WORK/releases.json" > "$WORK/next"
    mv "$WORK/next" "$WORK/releases.json" ;;
  "api repos/owner/repo/commits/main")
    if [ -n "$HEAD_ERROR" ]; then echo "$HEAD_ERROR" >&2; exit 1; fi
    echo "$MAIN_HEAD" ;;
  "api repos/owner/repo/compare/$GITHUB_SHA...$MAIN_HEAD") echo "$STATUS" ;;
  "api repos/owner/repo/contents/.github?ref=$GITHUB_SHA") echo "$OWN_WORKFLOWS" ;;
  "api repos/owner/repo/contents/.github?ref=$MAIN_HEAD") echo "$MAIN_WORKFLOWS" ;;
  "api --paginate")
    case "$3" in *"/releases?"*)
      while [ "$#" -gt 0 ] && [ "$1" != --jq ]; do shift; done
      jq -r "$2" "$WORK/releases.json" ;;
    esac ;;
  "api -X")
    if [ -n "$DELETE_ERROR" ]; then echo "$DELETE_ERROR" >&2; exit 1; fi
    jq --argjson id "${4##*/}" 'map(select(.id != $id))' "$WORK/releases.json" > "$WORK/next"
    mv "$WORK/next" "$WORK/releases.json" ;;
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
        upload_error="",
        releases=(),
        delete_error="",
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
            (work / "releases.json").write_text(json.dumps(list(releases)), encoding="utf-8")
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
                    "UPLOAD_ERROR": upload_error,
                    "DELETE_ERROR": delete_error,
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
            listed = json.loads((work / "releases.json").read_text(encoding="utf-8"))
            self.drafts_left = [r["id"] for r in listed if r["draft"] and r["tag_name"] == tag]
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
        self.assertEqual(self.calls(calls, "api -X DELETE"), [])

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

    def test_a_failed_upload_drops_its_draft_and_fails(self):
        # As in run 40950002022, whose draft of v0.1.0-dev.2859 stayed behind (#2024).
        done, calls = self.run_step(refusals=0, upload_error="HTTP 408: Request Timeout")
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release upload")), 4)
        self.assertEqual(self.calls(calls, "release edit"), [])
        deletes = self.calls(calls, "api -X DELETE")
        self.assertEqual(deletes, ["api -X DELETE repos/owner/repo/releases/7"])
        self.assertEqual(self.drafts_left, [])

    def test_a_published_release_sweeps_only_dev_drafts_older_than_a_day(self):
        done, calls = self.run_step(refusals=0, releases=SWEPT_AND_KEPT)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release edit")), 1)
        deletes = self.calls(calls, "api -X DELETE")
        self.assertEqual(deletes, ["api -X DELETE repos/owner/repo/releases/11"])

    def test_a_failed_sweep_only_warns(self):
        done, calls = self.run_step(
            refusals=0, releases=SWEPT_AND_KEPT, delete_error="HTTP 422: Validation Failed"
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("::warning::", done.stdout + done.stderr)
        self.assertEqual(len(self.calls(calls, "release edit")), 1)


def release(release_id, tag, days_old, draft=True):
    created = datetime.now(timezone.utc) - timedelta(days=days_old)
    return {
        "id": release_id,
        "tag_name": tag,
        "draft": draft,
        "created_at": created.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


# Only 11 is swept: a dev draft a day and more old. A fresh draft may be a running job's, a nightly
# isn't a dev build, a published release is never touched, the tag must be a dev tag in full, and
# this run's own tag (v0.1.0-dev.1) is never swept.
SWEPT_AND_KEPT = (
    release(11, "v0.1.0-dev.2859", 2),
    release(12, "v0.1.0-dev.3400", 0.5),
    release(13, "v0.1.0-nightly.20261101", 5),
    release(14, "v0.1.0-dev.2860", 5, draft=False),
    release(15, "v0.1.0-dev.2861-x", 5),
    release(16, "v0.1.0-dev.1", 5),
)


if __name__ == "__main__":
    unittest.main()
