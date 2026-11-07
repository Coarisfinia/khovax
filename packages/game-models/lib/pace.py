"""The player's pace for the motion check (#2128, #2142): how fast the game moves the player
across the ground, in metres a second, which player_clips.py prints for the check to measure the
walk and the run at."""

import math
import os

# Where the game's core scripts lie (packages/game/core/).
CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "game", "core")
# A tile's centre is sqrt(3) from its neighbour's.
TILE = math.sqrt(3.0)


def player(core=CORE):
    """A tile every Tuning.MOVE_TICKS, 6 ticks at 20 a second, copied by hand from `core`."""
    return TILE / 0.3
