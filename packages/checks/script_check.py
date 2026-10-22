"""Godot's script check on every tracked script, warnings as errors (project.godot), one Godot per
script but as many at once as the machine has cores (#923). Every failing script is named, not
only the first. A script fails when Godot exits non-zero or when its output has an ERROR: line,
even with exit 0 (such as a load cycle through a preloaded scene, #964).

    [GODOT=<binary>] uv run --locked packages/checks/script_check.py

GODOT defaults to `godot`.
"""

import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from annotations import error
from git_files import git_files

# A script error can leave Godot running forever, so every check has a time limit.
TIMEOUT_SECONDS = 60


def check(godot: str, script: str) -> tuple[str, str | None]:
    """Godot's output for the script, and why it fails (None when it passes)."""
    command = [godot, "--headless", "--path", ".", "--check-only", "-s", f"res://{script}"]
    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        return decoded(expired.output), "fails Godot's script check (timed out)"
    except OSError as error:
        return str(error), "fails Godot's script check"
    output = decoded(result.stdout)
    if result.returncode != 0:
        return output, "fails Godot's script check"
    if any(line.startswith("ERROR:") for line in output.split("\n")):
        return output, "Godot's script check logs an error"
    return output, None


def decoded(output: bytes | None) -> str:
    """Godot's output as text, without its trailing newlines."""
    return (output or b"").decode("utf-8", errors="replace").rstrip("\n")


def main() -> int:
    # The game's project folder (#1101): the scripts' paths below are relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    godot = os.environ.get("GODOT") or "godot"
    scripts = git_files("*.gd")
    with ThreadPoolExecutor(max_workers=os.process_cpu_count()) as pool:
        results = list(pool.map(lambda script: check(godot, script), scripts))
    # The outputs in the scripts' order, so they don't interleave.
    failed = 0
    for script, (output, failure) in zip(scripts, results, strict=True):
        print(output)
        if failure:
            print(error(script, failure))
            failed += 1
    print(f"{len(scripts)} scripts checked, {failed} failed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
