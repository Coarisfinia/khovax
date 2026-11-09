"""Tests that the player's pace (lib/pace.py), which the motion check measures the player's run
at, follows the game's own Tuning.MOVE_TICKS, Simulation.TICKS_PER_SECOND (#2142) and PlayerView's
MODEL_SCALE (#2128): a copy of the game's scripts with any of them changed changes the pace, so
the check never goes on measuring the old one.

    uv run --locked --package khovax-game-models src/game-models/test_pace.py

It prints each case and `PACE TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import math
import os
import re
import shutil
import sys
import tempfile

from game_shared import log

from lib import pace

# Case: (the constant, its file, the value to set it to), or None for the game's own.
CASES = {
    "the game's": None,
    "MOVE_TICKS 8": ("MOVE_TICKS", "tuning.gd", 8),
    "TICKS_PER_SECOND 30": ("TICKS_PER_SECOND", "simulation.gd", 30),
    "MODEL_SCALE 2": ("MODEL_SCALE", "player_view.gd", 2),
}


def value(folder, name, script):
    """The constant `name` as `folder/script` declares it."""
    with open(os.path.join(folder, script), encoding="utf-8") as found:
        return float(re.search(r"^const %s: \w+ = ([\d.]+)" % name, found.read(), re.MULTILINE).group(1))


def changed(folder, change):
    """A copy of the game's tuning.gd, simulation.gd and player_view.gd in `folder`, with `change`
    made."""
    for script in ("tuning.gd", "simulation.gd"):
        shutil.copy(os.path.join(pace.CORE, script), folder)
    shutil.copy(pace.VIEW, folder)
    if change is not None:
        name, script, number = change
        path = os.path.join(folder, script)
        with open(path, encoding="utf-8") as found:
            text = found.read()
        text, count = re.subn(r"^(const %s: \w+ = )[\d.]+" % name, r"\g<1>%d" % number, text, flags=re.MULTILINE)
        if count != 1:
            raise SystemExit("%s declares no %s" % (script, name))
        with open(path, "w", encoding="utf-8") as found:
            found.write(text)
    return folder


def main():
    passed = True
    for case, change in CASES.items():
        with tempfile.TemporaryDirectory() as folder:
            core = changed(folder, change)
            want = (pace.TILE * value(core, "TICKS_PER_SECOND", "simulation.gd") / value(core, "MOVE_TICKS", "tuning.gd")
                    / value(core, "MODEL_SCALE", "player_view.gd"))
            got = pace.player(core, os.path.join(core, "player_view.gd"))
        right = math.isclose(got, want)
        passed = passed and right
        line = "%s %s: pace %.3f m/s, the game's ticks make it %.3f" % ("ok" if right else "FAIL", case, got, want)
        if right:
            log.info("PACE TEST " + line)
        else:
            log.error("PACE TEST " + line)
    log.info("PACE TEST: %s" % ("PASS" if passed else "FAIL"))
    sys.exit(0 if passed else 1)


main()
