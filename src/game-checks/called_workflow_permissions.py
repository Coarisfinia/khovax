"""Fails when a workflow calls another one (`uses: ./.github/workflows/<file>.yml`) without granting
every permission the called one's jobs ask for (#2352). GitHub refuses such a run before any job
starts, whatever the jobs' `if:` says, and only the caller's own trigger shows it: nightly.yml calls
ci.yml, so a permission added to a ci.yml job stopped every nightly without a push or a pull
request seeing it.

A job without its own `permissions:` has its workflow's. A called workflow's job that has neither
gets what its caller grants, so it can't ask for more.

    uv run --locked --package khovax-game-checks src/game-checks/called_workflow_permissions.py
"""

import re
import sys
from pathlib import Path

from game_shared import log

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github/workflows"
LEVELS = {"none": 0, "read": 1, "write": 2}
# A mapping's `key: value` line, its value a plain word and maybe a comment after it.
ENTRY = re.compile(r"( *)([A-Za-z0-9_-]+):\s*([^#\s]*)\s*(#.*)?")
CALL = re.compile(r"\./\.github/workflows/([A-Za-z0-9_.-]+\.ya?ml)")

Permissions = dict[str, str]


class Workflow:
    """What the check reads of a workflow: its own permissions, and each job's permissions and
    called workflow (None where it has none)."""

    def __init__(self) -> None:
        self.permissions: Permissions | None = None
        self.jobs: dict[str, tuple[Permissions | None, str | None]] = {}


def read(text: str) -> Workflow:
    """The workflow in `text`, read by indentation: `jobs:` and `permissions:` at the top, each
    job two spaces in, its keys four. A `permissions:` that isn't a mapping of `scope: level`
    lines (or `{}`) raises, so a form this can't read never passes."""
    workflow = Workflow()
    job: str | None = None
    in_jobs = False
    # The permissions being read, and the indent of their `permissions:` line.
    block: Permissions | None = None
    block_indent = -1
    for line in text.split("\n"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = ENTRY.fullmatch(line)
        indent = len(line) - len(line.lstrip())
        if block is not None:
            if indent > block_indent:
                if match is None or match[3] not in LEVELS:
                    raise ValueError(f"a permission this can't read: {line.strip()}")
                block[match[2]] = match[3]
                continue
            block = None
        if match is None:
            continue
        key, value = match[2], match[3]
        if indent == 0:
            in_jobs = key == "jobs"
            job = None
            if key == "permissions":
                workflow.permissions = start(value)
                block, block_indent = workflow.permissions, 0
        elif in_jobs and indent == 2:
            job = key
            workflow.jobs[job] = (None, None)
        elif in_jobs and job is not None and indent == 4:
            permissions, called = workflow.jobs[job]
            if key == "permissions":
                permissions = start(value)
                block, block_indent = permissions, 4
            elif key == "uses" and (call := CALL.fullmatch(value.strip("\"'"))):
                called = call[1]
            workflow.jobs[job] = (permissions, called)
    return workflow


def start(value: str) -> Permissions:
    """The mapping a `permissions:` line opens: empty, its lines to follow, or `{}`."""
    if value not in ("", "{}"):
        raise ValueError(f"permissions given as {value!r}, not as one line per scope")
    return {}


def short(granted: Permissions, asked: Permissions) -> list[str]:
    """Each scope `asked` for above what `granted` gives, as "scope: level (granted)"."""
    return [
        f"{scope}: {level} (granted {granted.get(scope, 'none')})"
        for scope, level in sorted(asked.items())
        if LEVELS[level] > LEVELS[granted.get(scope, "none")]
    ]


def problems(workflows: dict[str, Workflow]) -> list[tuple[str, str]]:
    """Every call that grants less than its called workflow's jobs ask for, as (file, message)."""
    found = []
    for name, workflow in sorted(workflows.items()):
        for job, (own, called) in workflow.jobs.items():
            if called is None:
                continue
            target = workflows.get(called)
            if target is None:
                found.append((name, f"job {job} calls {called}, which isn't in the workflows"))
                continue
            granted = own if own is not None else workflow.permissions
            if granted is None:
                found.append((name, f"job {job} calls {called} but grants it no permissions"))
                continue
            for inner, (asked, _called) in target.jobs.items():
                asked = asked if asked is not None else target.permissions
                # Neither the job nor its workflow names any: it gets what the caller grants.
                if asked is not None and (missing := short(granted, asked)):
                    found.append(
                        (
                            name,
                            f"job {job} calls {called}, whose job {inner} asks for more than it "
                            f"grants: {', '.join(missing)}",
                        )
                    )
    return found


def main() -> int:
    workflows = {path.name: read(path.read_text(encoding="utf-8")) for path in WORKFLOWS.glob("*.y*ml")}
    if not any(called for workflow in workflows.values() for _own, called in workflow.jobs.values()):
        # Reading no call at all would pass whatever the files say.
        log.error("no workflow calls another: the check read nothing")
        return 1
    found = problems(workflows)
    for name, message in found:
        log.error(message, str(WORKFLOWS / name))
    if not found:
        log.info("every called workflow gets the permissions its jobs ask for")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
