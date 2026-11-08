"""The player's pace for the motion check (#2128, #2142): how fast the game moves the player
across the ground, in metres a second, which player_clips.py prints for the check to measure the
walk and the run at. It reads the game's own numbers, so a change there changes the pace the check
measures at."""

import math
import os
import re

# Where the game's core scripts lie (packages/game/core/).
CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "game", "core")
# A tile's centre is sqrt(3) from its neighbour's.
TILE = math.sqrt(3.0)


def constant(path, name):
    """The whole number the GDScript at `path` declares as `const <name>: int = <number>`."""
    with open(path, encoding="utf-8") as found:
        match = re.search(r"^const %s: int = (\d+)\s*(#.*)?$" % re.escape(name), found.read(), re.MULTILINE)
    if match is None:
        raise RuntimeError("%s declares no `const %s: int = <number>`" % (path, name))
    return int(match.group(1))


def player(core=CORE):
    """A tile every Tuning.MOVE_TICKS ticks, at Simulation.TICKS_PER_SECOND ticks a second, as the
    game's core scripts in `core` declare them."""
    ticks = constant(os.path.join(core, "tuning.gd"), "MOVE_TICKS")
    rate = constant(os.path.join(core, "simulation.gd"), "TICKS_PER_SECOND")
    return TILE * rate / ticks
