"""Checks the rule change files (#736): each file's name and frontmatter, and that the folder is
append-only (#876): a file deleted or renamed would give the rules (RulesChanges, a digest of the
names of the files in core/rules_changes/) an id that older rules may already have had. Whether a
change needs a new file is the rules-compare job's (tools/replays/rules_compare.py).
<base> is the commit the change is compared with, e.g. HEAD^1 of a pull request's merge commit.

    uv run --locked tools/checks/rules_changes_check.py <base>
"""

import os
import re
import subprocess
import sys
from pathlib import Path

FOLDER = "core/rules_changes"
NAME = re.compile(r"([0-9]+)-[a-z0-9-]+\.md")


def deleted_since(base: str) -> list[str] | None:
    """The files under FOLDER that HEAD no longer has since base, or None when git can't compare
    them. Without rename detection, a renamed file shows as deleted (and another added)."""
    diff = subprocess.run(
        ["git", "diff", "-z", "--no-renames", "--name-only", "--diff-filter=D", base, "HEAD"]
        + ["--", FOLDER],
        stdout=subprocess.PIPE,
        text=True,
    )
    if diff.returncode != 0:
        return None
    return [path for path in diff.stdout.split("\0") if path]


def main() -> int:
    os.chdir(Path(__file__).resolve().parents[2])
    base = sys.argv[1]
    failed = False

    for entry in sorted(path for path in os.listdir(FOLDER) if not path.startswith(".")):
        file = f"{FOLDER}/{entry}"
        name = NAME.fullmatch(entry)
        if not name:
            print(f"::error file={file}::a rule change file is named <issue>-<slug>.md")
            failed = True
            continue
        # newline="": a carriage return stays, so a CRLF frontmatter fails as it did in the shell.
        text = Path(file).read_text(encoding="utf-8", newline="")
        lines = text.split("\n")
        # No pr (#758): the squash commit that added the file names it (git log --diff-filter=A).
        if lines[0:3:2] != ["---", "---"] or lines[1:2] != [f"issue: {name[1]}"]:
            print(
                f"::error file={file}::its frontmatter is its issue (the file's number), nothing"
                " else (no pr: git log finds it)"
            )
            failed = True
        if re.search(r"/pull/[0-9]", text):
            print(
                f"::error file={file}::it links its issue, not its pull request (git log finds"
                " that)"
            )
            failed = True

    deleted = deleted_since(base)
    if deleted is None:
        print(f"::error::git can't compare {FOLDER} with {base}")
        return 1
    for path in deleted:
        print(
            f"::error file={path}::a rule change file is never deleted or renamed: the folder is"
            " append-only"
        )
        failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
