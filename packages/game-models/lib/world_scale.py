"""The world's scale (#1837, from #1835): a hex's size and a wall's height against the player's
height, so buildings, walls, gates and props are sized alike. check_world_scale.py holds every
model to it, and a model script reads it from here to size its model.

The numbers are in metres, the game's world units:

- **the hex** is `HEX_SIZE` from its centre to a corner (HexLayout.SIZE), so one edge is
  `HEX_EDGE` long and the hex is `HEX_WIDTH` across its flats;
- **the player** is `PLAYER_HEIGHT` tall: the players' figure as PlayerView shows it, standing in
  its idle clip, without the parts it hides. The check measures the figure against it, so a new
  figure can't change the scale unseen;
- **a wall** is `WALL_HEIGHT` tall, a quarter above the player, so a room's walls hide what's
  inside from the camera until the walls fade (#1835).

A model built by a script here that isn't a monster (a prop in lib/footprint.py's sense: no rig,
or no Walk clip) names its kind in its script, `WORLD_SCALE = "<kind>"`, one of `KINDS`. Each
kind gives the range its height must be in, and an **edge piece** (a wall, a gate) runs along
one hex edge: Blender's X, centred on the origin at the edge's middle, `HEX_EDGE` long, so pieces
meet end to end at the hex's corners. A monster is sized against its hex instead (the footprint
check) and has no kind."""

import math

# The game's hex, centre to corner (HexLayout.SIZE), which is also one edge's length.
HEX_SIZE = 1.0
HEX_EDGE = HEX_SIZE
HEX_WIDTH = HEX_SIZE * math.sqrt(3.0)
# The players' figure, standing in its idle clip as PlayerView shows it; the check measures the
# figure and fails past `PLAYER_TOLERANCE` (a share) either way.
PLAYER_HEIGHT = 2.17
PLAYER_TOLERANCE = 0.03
# A wall stands a quarter above the player.
WALL_HEIGHT = 1.25 * PLAYER_HEIGHT
# How far an edge piece's length may stray from the edge's (a share), so pieces still meet.
EDGE_TOLERANCE = 0.03


class Kind:
    """A kind of model: the range its height must be in, in metres, and whether it's an edge piece
    (`HEX_EDGE` long along X)."""

    def __init__(self, low, high, edge, what):
        self.low, self.high, self.edge, self.what = low, high, edge, what


KINDS = {
    "prop": Kind(0.05 * PLAYER_HEIGHT, 1.5 * PLAYER_HEIGHT, False,
                 "a thing standing on one hex: a well, a campfire, a signpost, a stone"),
    "portal": Kind(1.1 * PLAYER_HEIGHT, 1.3 * WALL_HEIGHT, False,
                   "a gate on one hex the player walks through, standing above the player"),
    "wall": Kind(0.9 * WALL_HEIGHT, 1.1 * WALL_HEIGHT, True, "a wall piece along one hex edge"),
    "gate": Kind(1.1 * PLAYER_HEIGHT, 1.3 * WALL_HEIGHT, True,
                 "a passable piece along one hex edge, standing above the player"),
    "ruined_wall": Kind(0.15 * PLAYER_HEIGHT, 1.1 * WALL_HEIGHT, True,
                        "a broken wall piece along one hex edge, at most a wall's height"),
    "tower": Kind(1.1 * WALL_HEIGHT, 2.0 * WALL_HEIGHT, False,
                  "a tower at a hex corner, where walls meet, standing above them"),
    "ruin": Kind(0.15 * PLAYER_HEIGHT, 1.1 * WALL_HEIGHT, False,
                 "what's left of a tower or building, at most a wall's height"),
}


def bounds(points):
    """The (length along X, height) of `points`, an (n, 3) array in world space standing on the
    ground at the origin: the height is the highest point's."""
    return float(points[:, 0].max() - points[:, 0].min()), float(points[:, 2].max())


def judge(kind, length, height):
    """The report lines for a model of `kind` (a key of `KINDS`) `length` long along X and `height`
    tall, each `<ok|FAIL> <measure>: ...`, and whether it passes."""
    if kind not in KINDS:
        return ["FAIL kind: %r isn't one of %s" % (kind, ", ".join(sorted(KINDS)))], False
    rule = KINDS[kind]
    fits = rule.low <= height <= rule.high
    lines = ["%s height: %.2f m, %.2f players (%s %.2f to %.2f m)" % (
        "ok" if fits else "FAIL", height, height / PLAYER_HEIGHT, kind, rule.low, rule.high)]
    passed = fits
    if rule.edge:
        meets = abs(length - HEX_EDGE) <= EDGE_TOLERANCE * HEX_EDGE
        passed = passed and meets
        lines.append("%s length: %.2f m along X (an edge, %.2f m)" % (
            "ok" if meets else "FAIL", length, HEX_EDGE))
    return lines, passed


def judge_figure(height):
    """The report line for the players' figure standing `height` tall, and whether it's the
    player's height."""
    fits = abs(height - PLAYER_HEIGHT) <= PLAYER_TOLERANCE * PLAYER_HEIGHT
    return ["%s height: %.2f m (the player, %.2f m)" % ("ok" if fits else "FAIL", height, PLAYER_HEIGHT)], fits
