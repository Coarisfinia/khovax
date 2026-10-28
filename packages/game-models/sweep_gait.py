"""Builds a model over a small grid of its gait values and checks each build (#1524): instead of
hand-run rounds of build, check, read the logs and adjust, one run prints a short table of which
combinations pass, and for each failing one the limit it misses most and by how much.

    uv run --locked --package khovax-game-models packages/game-models/sweep_gait.py \
        packages/game-models/<name>.py packages/game/assets/<name>/<name>.glb \
        NAME=value,value,... [NAME=value,...] [--clips Walk,Run] [--jobs N] [--keep <folder>]

The script must offer the names in its GAIT (lib/tuning.py); the committed .glb's .import gives
the builds the game's clip rate and loops. Each combination is built in its own folder, then the
motion check (at the speeds the build prints), the ground check and the clearance check run on it
in their summary mode (lib/summary.py); `--jobs` combinations run at once. `--clips` counts only
those clips' misses (a gait's clips; a value like CROUCH reaches every clip). `--keep` keeps each
build in the folder, named after its values, so the passing one can be committed as it is; the
model is then built once more from its script with the chosen values written in."""

import argparse
import itertools
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

MODELS = Path(__file__).resolve().parent
sys.path.insert(0, str(MODELS))

from lib import summary  # noqa: E402

BLENDER = MODELS / "blender.py"
CHECKS = ("check_motion.py", "check_ground.py", "check_clearance.py")
SPEEDS = re.compile(r"^SPEEDS (.*)$", re.MULTILINE)


def blender(script: Path, args: list[str]) -> subprocess.CompletedProcess:
    command = [sys.executable, str(BLENDER), "--background", "--factory-startup", "--python", str(script),
               "--", *args]
    return subprocess.run(command, capture_output=True, text=True)


def failure(output: str) -> str:
    """What a failed build said last: its last error line, or its last line."""
    lines = [line.strip() for line in output.splitlines() if line.strip() and line.strip() != "Blender quit"]
    errors = [line for line in lines if "Error" in line or "error" in line or "FAIL" in line]
    return (errors or lines or ["no output"])[-1]


def worst(misses: list[dict]) -> dict:
    """The miss furthest past its limit, as a share of the limit (one without a number counts
    as furthest)."""
    def share(miss):
        if miss["value"] is None or float(miss["limit"]) == 0.0:
            return float("inf")
        return abs(float(miss["value"]) - float(miss["limit"])) / abs(float(miss["limit"]))
    return max(misses, key=share)


def describe(miss: dict) -> str:
    text = "%s %s %s" % (miss["check"], miss["clip"], miss["measure"])
    if miss["value"] is not None:
        by = abs(float(miss["value"]) - float(miss["limit"]))
        text += " %s %s %s %s (by %.2f)" % (miss["value"], miss["side"], miss["limit"], miss["unit"] or "", by)
    return text


def run(script: Path, glb: Path, values: dict, folder: Path, clips: set[str]) -> str:
    """Builds one combination into `folder` and checks it: `PASS`, or what fails."""
    folder.mkdir(parents=True, exist_ok=True)
    out = folder / glb.name
    shutil.copy(str(glb) + ".import", str(out) + ".import")
    built = blender(script, [str(out), *("%s=%s" % pair for pair in values.items())])
    if built.returncode != 0:
        return "build fails: " + failure(built.stdout + built.stderr)
    speeds = SPEEDS.search(built.stdout)
    misses, broken = [], []
    for check in CHECKS:
        args = [str(out), *(speeds.group(1).split() if speeds and check == "check_motion.py" else []), "--summary"]
        done = blender(MODELS / check, args)
        found = [match.groupdict() for match in map(summary.LINE.match, done.stdout.splitlines()) if match]
        if done.returncode != 0 and not found:
            broken.append("%s: %s" % (check, failure(done.stdout + done.stderr)))
        misses += [miss for miss in found if not clips or miss["clip"].split("/")[-1] in clips]
    if broken:
        return "check fails: " + "; ".join(broken)
    if not misses:
        return "PASS"
    more = " (+%d more)" % (len(misses) - 1) if len(misses) > 1 else ""
    return "FAIL " + describe(worst(misses)) + more


def grid(specs: list[str]) -> tuple[list[str], list[tuple[str, ...]]]:
    names, choices = [], []
    for spec in specs:
        name, _, values = spec.partition("=")
        if not values:
            raise SystemExit("expected NAME=value,value,..., not %r" % spec)
        names.append(name)
        choices.append(tuple(values.split(",")))
    return names, list(itertools.product(*choices))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("script", type=Path)
    parser.add_argument("glb", type=Path)
    parser.add_argument("values", nargs="+", help="NAME=value,value,...")
    parser.add_argument("--clips", default="", help="count only these clips' misses (comma-separated)")
    parser.add_argument("--jobs", type=int, default=max(1, min(4, (os.cpu_count() or 2) // 3)))
    parser.add_argument("--keep", type=Path, help="keep each build in this folder")
    options = parser.parse_args()
    names, combinations = grid(options.values)
    clips = {clip for clip in options.clips.split(",") if clip}
    base = options.keep or Path(tempfile.mkdtemp(prefix="sweep-gait-"))
    folders = [base / "_".join("%s-%s" % pair for pair in zip(names, combo)) for combo in combinations]
    try:
        with ThreadPoolExecutor(options.jobs) as pool:
            results = list(pool.map(lambda job: run(options.script.resolve(), options.glb.resolve(),
                                                    dict(zip(names, job[0])), job[1], clips),
                                    zip(combinations, folders)))
    finally:
        if options.keep is None:
            shutil.rmtree(base, ignore_errors=True)
    passing = sum(result == "PASS" for result in results)
    print("SWEEP %s: %d of %d pass%s" % (options.script.name, passing, len(results),
                                          " (clips %s)" % ", ".join(sorted(clips)) if clips else ""))
    print("| %s | result |" % " | ".join(names))
    print("|" + "---|" * (len(names) + 1))
    for combo, result in zip(combinations, results):
        print("| %s | %s |" % (" | ".join(combo), result))
    return 0 if passing else 1


if __name__ == "__main__":
    sys.exit(main())
