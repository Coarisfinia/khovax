"""Compares how this commit plays with how its parent plays (#876): two outcome reports
(tests/replays/outcomes.gd), one from each commit's build. When they differ, the commit must add a
rule change file to core/rules_changes/, or the check fails. Prints a Markdown summary for the job:
which replay, and which checkpoint in it, diverges first.
CI runs this script from the parent's checkout, so a pull request can't weaken its own check.
What it can't compare fails too (#889): a reference replay removed or its inputs changed, the APK
flow's scripts changed, or the outcome report itself changed. The label `outcomes-change` on the
pull request allows that (#899: the agent adds it and says why, the owner's approval is the gate),
which CI passes on as OUTCOMES_CHANGE=true.

    [OUTCOMES_CHANGE=true] uv run --locked packages/game-replays/rules_compare.py \\
        <parent's report> <this commit's report> <parent>

Run from this commit's repository root; <parent> is the commit the parent's report was made from.
The game's paths are read in each commit's own layout: under packages/game (#1101), or at the
root in a parent from before that move.
"""

import json
import os
import subprocess
import sys
from typing import Any

# The game's folder (#1101); the paths below are inside it.
GAME = "packages/game"
REPLAYS = "tests/replays"
FOLDER = "core/rules_changes"
# The APK's flow and its headless runner.
FLOW_SCRIPTS = ("tests/apk/apk_flow.gd", "tests/e2e/test_apk_flow.gd")
# This script, which no commit may remove (see main).
SELF = "packages/game-replays/rules_compare.py"


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(("git", *args), capture_output=True, text=True, check=False)


def game_path(commit: str, path: str) -> str:
    """A game file's path from the repository's root in that commit: under GAME, or at the root in
    a commit from before the game moved there (#1101)."""
    if git("cat-file", "-e", f"{commit}:{GAME}/project.godot").returncode == 0:
        return f"{GAME}/{path}"
    return path


def commit_path(commit: str, path: str) -> str:
    """A game file in that commit, as git names a blob: <commit>:<path from the root>."""
    return f"{commit}:{game_path(commit, path)}"


def changed(parent: str, *paths: str) -> bool:
    """Whether any of these game files differ between the parent and this commit, or one is
    missing from either."""
    return any(
        git("diff", "--quiet", commit_path(parent, path), commit_path("HEAD", path)).returncode != 0
        for path in paths
    )


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True)


def same(a: Any, b: Any) -> bool:
    """JSON equality as jq has it: 1 and 1.0 are equal, true and 1 aren't."""
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[key], b[key]) for key in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    numbers = (int, float)
    if type(a) in numbers and type(b) in numbers:
        return a == b
    return type(a) is type(b) and a == b


def inputs(commit: str, name: str) -> str | None:
    """A replay's inputs: everything but what a rehash writes (Replay.rehash), which a reference
    replay no longer holds (#876), as canonical JSON; None when the commit has no such replay."""
    shown = git("show", commit_path(commit, f"{REPLAYS}/{name}"))
    if shown.returncode != 0:
        return None
    replay = json.loads(shown.stdout)
    for key in ("rules", "checkpoints", "features"):
        replay.pop(key, None)
    return canonical(replay)


def first_divergence(before: dict[str, Any], after: dict[str, Any]) -> str:
    """Where two reports first differ for one replay: its first differing checkpoint, else its
    final state; empty when they match."""
    ticks = sorted({int(tick) for tick in (*before["checkpoints"], *after["checkpoints"])})
    for tick in ticks:
        key = str(tick)
        if not same(before["checkpoints"].get(key), after["checkpoints"].get(key)):
            return f"the checkpoint at tick {tick}"
    if not same(before.get("final"), after.get("final")):
        return "the final state"
    return ""


def warn(message: str) -> None:
    print(f"::warning::{message}", file=sys.stderr)


def main(parent_path: str, head_path: str, parent: str) -> int:
    labelled = os.environ.get("OUTCOMES_CHANGE", "false") == "true"
    # CI runs the parent's copy of this script, and falls back to the commit's own only while the
    # parent has none (the pull requests that added it, #876, moved it, #1037, #1101 and #1114,
    # and ported it to Python, #1039). So no commit may remove it, or the next one could bring its
    # own.
    if git("cat-file", "-e", f"HEAD:{SELF}").returncode != 0:
        print(f"::error::{SELF} is removed: the comparison with the parent can't go", file=sys.stderr)
        return 1
    with open(parent_path, encoding="utf-8") as file:
        parent_report = json.load(file)
    with open(head_path, encoding="utf-8") as file:
        head_report = json.load(file)

    print("### Rules: this commit compared with its parent")
    print()
    print("| Played | Compared with the parent |")
    print("| --- | --- |")
    diverged: list[str] = []
    unchecked: list[str] = []
    before_replays = parent_report["replays"]
    after_replays = head_report["replays"]
    for name in sorted({*before_replays, *after_replays}):
        if name not in after_replays:
            verdict = "removed: nothing to compare"
            unchecked.append(f"`{name}` is removed")
        elif name not in before_replays:
            verdict = "new: nothing to compare"
        elif inputs(parent, name) != inputs("HEAD", name):
            verdict = "its inputs changed: not compared"
            unchecked.append(f"`{name}`'s inputs changed")
        else:
            where = first_divergence(before_replays[name], after_replays[name])
            if not where:
                verdict = "plays the same"
            else:
                verdict = f"**differs**, first at {where}"
                diverged.append(f"`{name}` at {where}")
        print(f"| `{name}` | {verdict} |")
        if "not compared" in verdict or "nothing to compare" in verdict:
            warn(f"{REPLAYS}/{name}: {verdict}")

    def flow_final(report: dict[str, Any]) -> Any:
        return (report.get("apk_flow") or {}).get("final")

    if changed(parent, *FLOW_SCRIPTS):
        verdict = "its script changed: not compared"
        unchecked.append("the APK flow's scripts changed")
        warn(f"the APK flow: {verdict}")
    elif same(flow_final(parent_report), flow_final(head_report)):
        verdict = "plays the same"
    else:
        verdict = "**differs** in its final state"
        diverged.append("the APK flow's final state")
    print(f"| the APK flow | {verdict} |")
    print()

    if changed(parent, f"{REPLAYS}/outcomes.gd"):
        unchecked.append(f"the outcome report (`{REPLAYS}/outcomes.gd`) changed")
        warn(f"{REPLAYS}/outcomes.gd changed: check that it still reports what the game does")

    failed = 0
    if unchecked:
        print("Not everything could be compared with the parent:")
        for what in unchecked:
            print(f"- {what}")
        print()
        if labelled:
            print(
                "The pull request is labelled `outcomes-change`, so that's allowed: its description"
                " says why."
            )
        else:
            print(
                "If that's intended, label the pull request `outcomes-change` and say why in it"
                " (#889, #899)."
            )
            print(
                "::error::not everything could be compared with the parent, and the pull request"
                " isn't labelled outcomes-change",
                file=sys.stderr,
            )
            failed = 1
        print()

    if not diverged:
        print("This commit plays like its parent.")
        return failed
    print("This commit plays differently from its parent. It diverges first in:")
    for where in diverged:
        print(f"- {where}")
    print()

    # Without rename detection, a renamed file shows as deleted and added. The folder is
    # append-only: a commit that deletes or renames a file declares nothing, even if it adds one.
    # The folder in both commits' layouts: the commit that moved the game (#1101) deletes every
    # file at the old path, so it can't declare a change.
    folders = sorted({game_path(parent, FOLDER), game_path("HEAD", FOLDER)})

    def files(kind: str) -> list[str]:
        listed = git("diff", "--no-renames", "--name-only", f"--diff-filter={kind}", parent, "HEAD",
                     "--", *folders)  # fmt: skip
        return listed.stdout.splitlines()

    added = files("A")
    if files("D"):
        print(
            "It deletes or renames a rule change file, so it declares nothing: the folder is"
            " append-only."
        )
    elif not added:
        print(
            f"It adds no rule change file: add one to `{FOLDER}/` if that's intended (see"
            " RulesChanges), or find what changed the game."
        )
    else:
        print(
            "It declares a rule change, so that's intended: check that the change above is the one"
            " declared in:"
        )
        for path in added:
            print(f"- `{path}`")
        return failed
    print(
        f"::error::this commit plays differently from its parent without a new file in {FOLDER}/",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
