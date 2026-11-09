"""Runs a Blender check on each .glb in a list, one Blender per .glb and as many at once as the
machine has cores (#2031), so a check over every model takes a share of the time it takes one
after the other.

    uv run --locked --package khovax-game-models src/game-models/blender_each.py \
        <list> <check.py> [<arg> ...]

The list is the .glb files separated by NUL bytes, as changed_models.py writes it. Each runs as
`blender.py --background --factory-startup --python <check.py> -- <glb> [<arg> ...]`, the biggest
file first, so the slowest models don't start last. Each run's output is printed whole, in that
order once the run has ended, so the runs' lines never mix. It exits 1 when any run fails, naming
each, and 0 when the list is empty."""

import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from game_shared import log

BLENDER = Path(__file__).resolve().parent / "blender.py"


def run(glb: str, check: str, args: list[str]) -> tuple[str, int, str]:
    command = [sys.executable, str(BLENDER), "--background", "--factory-startup", "--python", check, "--", glb,
               *args]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return glb, result.returncode, result.stdout


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    listing, check, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    glbs = sorted((glb for glb in Path(listing).read_text().split("\0") if glb), key=lambda glb: -os.path.getsize(glb))
    failed = []
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        for future in [pool.submit(run, glb, check, args) for glb in glbs]:
            glb, code, output = future.result()
            print(output, end="", flush=True)
            if code != 0:
                failed.append(glb)
    for glb in failed:
        log.error(f"{os.path.basename(check)} failed on this model", glb)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
