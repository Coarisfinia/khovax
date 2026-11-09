"""The player's pace for the motion check (#2128, #2142): how fast the game moves the player
across the ground, in metres a second of the clips' own units, which player_clips.py prints for the
check to measure the run at. It reads the game's own numbers, so a change there changes the pace
the check measures at."""

import math
import os
import re

# Where the game's core scripts lie (src/game/core/).
GAME = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "game")
CORE = os.path.join(GAME, "core")
# The view that draws the player's body, at its MODEL_SCALE.
VIEW = os.path.join(GAME, "slices", "players", "look", "player_view.gd")
# A tile's centre is sqrt(3) from its neighbour's.
TILE = math.sqrt(3.0)


def constant(path, name):
    """The whole number the GDScript at `path` declares as `const <name>: int = <number>`."""
    with open(path, encoding="utf-8") as found:
        match = re.search(r"^const %s: int = (\d+)\s*(#.*)?$" % re.escape(name), found.read(), re.MULTILINE)
    if match is None:
        raise RuntimeError("%s declares no `const %s: int = <number>`" % (path, name))
    return int(match.group(1))


def scale(view=VIEW):
    """The MODEL_SCALE the GDScript at `view` draws the body at (`const MODEL_SCALE: float = <n>`)."""
    with open(view, encoding="utf-8") as found:
        match = re.search(r"^const MODEL_SCALE: float = ([\d.]+)\s*(#.*)?$", found.read(), re.MULTILINE)
    if match is None:
        raise RuntimeError("%s declares no `const MODEL_SCALE: float = <number>`" % view)
    return float(match.group(1))


def player(core=CORE, view=VIEW):
    """A tile every Tuning.MOVE_TICKS ticks, at Simulation.TICKS_PER_SECOND ticks a second, as the
    game's core scripts in `core` declare them, in the clips' own units: the view at `view` draws
    the body larger than the clips are built, so its feet cover that much more ground."""
    ticks = constant(os.path.join(core, "tuning.gd"), "MOVE_TICKS")
    rate = constant(os.path.join(core, "simulation.gd"), "TICKS_PER_SECOND")
    return TILE * rate / ticks / scale(view)
