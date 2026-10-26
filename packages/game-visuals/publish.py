"""Publishes pictures for a pull request's description on the assets branch (an orphan branch that
is never merged), safely while other agents publish too (#1428).

It never touches a checkout: it builds the commit in a throwaway index on top of the newest
origin/assets (`git hash-object`, `git commit-tree`) and pushes it without force. When another
publish got there first, the push is refused and it starts over on the new
origin/assets, so nobody's pictures are lost and no shared worktree is ever reset.

Each file lands at the branch's top level under its own name, which the description links as
https://github.com/Coarisfinia/khovax/blob/assets/<name>?raw=true. `--remove` takes paths off the
branch again.

    uv run --locked --package khovax-game-visuals packages/game-visuals/publish.py \
        pr-<n>-<what>.png ... [--remove <path> ...]
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from game_shared import log

BRANCH = "assets"
ATTEMPTS = 8
# How a push says another one got there first: a non-fast-forward, or, when both reach GitHub at
# the same moment, the branch moving under its ref lock.
MOVED = ("non-fast-forward", "fetch first", "cannot lock ref")
URL = "https://github.com/Coarisfinia/khovax/blob/assets/{}?raw=true"


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish pictures on the assets branch.")
    parser.add_argument("files", nargs="*", type=Path, help="pictures to add or replace")
    parser.add_argument("--remove", nargs="+", default=[], metavar="PATH", help="paths to take off")
    args = parser.parse_args()
    if not args.files and not args.remove:
        parser.error("name a file to publish or a path to remove")
    missing = [str(file) for file in args.files if not file.is_file()]
    if missing:
        log.error(f"no such file: {', '.join(missing)}")
        return 1

    for attempt in range(1, ATTEMPTS + 1):
        if git("fetch", "-q", "--no-write-fetch-head", "origin",
               f"+refs/heads/{BRANCH}:refs/remotes/origin/{BRANCH}", check=False).returncode != 0:
            log.warning(f"fetching origin/{BRANCH} failed (attempt {attempt}), trying again")
            continue
        parent = git("rev-parse", f"origin/{BRANCH}").stdout.strip()
        commit = build_commit(parent, args.files, args.remove)
        if commit is None:
            log.info(f"origin/{BRANCH} already holds these files: nothing to publish")
            break
        push = git("push", "-q", "origin", f"{commit}:refs/heads/{BRANCH}", check=False)
        if push.returncode == 0:
            break
        if not any(reason in push.stderr for reason in MOVED):
            log.error(f"pushing to {BRANCH} failed:\n{push.stderr.strip()}")
            return 1
        log.info(f"another publish got there first (attempt {attempt}): starting over on it")
    else:
        log.error(f"gave up after {ATTEMPTS} attempts: {BRANCH} kept moving or couldn't be fetched")
        return 1

    for file in args.files:
        log.info(f"![{file.stem}]({URL.format(file.name)})")
    return 0


def build_commit(parent: str, files: list[Path], removals: list[str]) -> str | None:
    """A commit on top of parent with the files added and the removals gone, built in a throwaway
    index so no checkout changes; None when its tree would be parent's."""
    with tempfile.TemporaryDirectory() as scratch:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(scratch) / "index")}
        git("read-tree", parent, env=env)
        for file in files:
            blob = git("hash-object", "-w", "--", str(file)).stdout.strip()
            git("update-index", "--add", "--cacheinfo", f"100644,{blob},{file.name}", env=env)
        for path in removals:
            git("update-index", "--force-remove", "--", path, env=env)
        tree = git("write-tree", env=env).stdout.strip()
    if tree == git("rev-parse", f"{parent}^{{tree}}").stdout.strip():
        return None
    parts = [f"add {', '.join(file.name for file in files)}"] if files else []
    parts += [f"remove {', '.join(removals)}"] if removals else []
    message = f"Assets: {'; '.join(parts)}"
    return git("commit-tree", tree, "-p", parent, "-m", message).stdout.strip()


def git(*args: str, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=check, env=env)


if __name__ == "__main__":
    sys.exit(main())
