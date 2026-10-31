"""Checks that a monster stays within its hex (#1520): every frame of every clip, how far the
deformed mesh reaches across the hex the game stands it on, seen from above, from lib/footprint.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_footprint.py -- <model.glb> [<model.glb> ...]

The base rules, which CI enforces (the owner, on #1514, #1533, #1528 and #1641), as the largest
reach over the hex's inradius (1.00 at its edge; the limits are in lib/footprint.py):

    regular monster             rest pose 0.95   Attack 1.30   other clips 1.05
    boss, enraged or stronger   rest pose 1.05   Attack 1.30   other clips 1.10
    (a model in LARGE)
    prop (no rig, or no Walk)   rest pose 0.95                 every clip  1.00

It prints a line for the rest pose and one per clip (the largest reach and its frame, and the
limit) and `FOOTPRINT CHECK: PASS` or `FAIL` (and exits 1 on a fail), through game_shared.log
(#1115): a failing line is an error on the .glb. It checks every model built by a script here,
monsters and props alike, a static one by its rest pose; nothing is let off through a list
(#1641). A pack's model (no script here: the players' and people's figure, the chest) is measured
as each view that stands it on the board shows it (#1652, lib/views.py): at the view's scale,
without the parts it hides, standing in its idle clip rather than its T-pose and in the clips it
plays, against a prop's limits. Two kinds aren't things standing on a hex and are left out by what
they are: a tile's decoration (a model a tile blueprint names), which is the tile's own look (the
owner, on #1651), and a pack's model no view puts on the board (an item, shown only in the gear
panel's pictures). So CI runs it on every .glb.
The clip rate comes from the .glb's .import, as the game imports it.

A clip that still fails today waits in KNOWN with the issue that fixes it: it prints its numbers
and doesn't fail the check. The list only shrinks: a clip on it that passes fails the check
until it's taken off."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import footprint, imported, known, views, world_scale  # noqa: E402

# The Godot project, whose views show the packs' models.
GAME = os.path.join(os.path.dirname(HERE), "game")

# The models (by .glb name) of bosses, enraged or stronger monsters, which may reach past their hex.
LARGE = {"fohossa"}

# (model, clip or "rest" for the rest pose) that fails today, with the issue that fixes it; that
# issue takes its entries off.
KNOWN = {
    ("Rogue", "Running_A"): 1702,
    ("mana_wolf", "rest"): 1527,
    ("mana_wolf", "Attack"): 1527,
    ("mana_wolf", "Channel"): 1527,
    ("mana_wolf", "ChannelEnd"): 1527,
    ("mana_wolf", "ChannelStart"): 1527,
    ("mana_wolf", "Faint"): 1527,
    ("mana_wolf", "Feed"): 1527,
    ("mana_wolf", "Hit"): 1527,
    ("mana_wolf", "Idle"): 1527,
    ("mana_wolf", "Run"): 1527,
    ("mana_wolf", "Sleep"): 1527,
    ("mana_wolf", "Walk"): 1527,
    ("ombulumo", "rest"): 1528,
    ("ombulumo", "Attack"): 1528,
    ("ombulumo", "Channel"): 1528,
    ("ombulumo", "ChannelEnd"): 1528,
    ("ombulumo", "ChannelStart"): 1528,
    ("ombulumo", "Faint"): 1528,
    ("ombulumo", "Feed"): 1528,
    ("ombulumo", "Hit"): 1528,
    ("ombulumo", "Idle"): 1528,
    ("ombulumo", "Run"): 1528,
    ("ombulumo", "Sleep"): 1528,
    ("ombulumo", "Walk"): 1528,
}


def measure(model, glb, fps, scripts):
    """The report lines for `model`: its own when a script here builds it, else one set per view
    that shows the pack's model on the board, each line named after its view. None when nothing
    stands it on the board."""
    if os.path.exists(os.path.join(HERE, model + ".py")):
        rig = imported.load_view(glb, fps)
        lines, _passed = footprint.report(
            rig, footprint.meshes(rig, bpy.data.objects), footprint.limits(rig, model in LARGE))
        return [(line, "") for line in lines]
    shown = views.find(GAME, model, scripts)
    if not shown:
        return None
    lines = []
    for view in shown:
        rig = imported.load_view(glb, fps, view.scale)
        meshes = [obj for obj in footprint.meshes(rig, bpy.data.objects) if obj.name not in view.hidden]
        # A figure stands in its idle clip and plays only the view's clips; a static model has
        # only its rest pose. It's held to a prop's limits: it neither walks on nor strikes.
        standing = view.standing if rig is not None else None
        report, _passed = footprint.report(rig, meshes, footprint.PROP, view.clips, standing)
        tag = " (%s, scale %.2f)" % (view.name, view.scale)
        lines += [(line, tag) for line in report]
    return lines


def main():
    glbs = sys.argv[sys.argv.index("--") + 1:]
    tile_looks = views.decorations(GAME)
    scripts = views.Scripts(GAME)
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        if model in tile_looks:
            # The tile's own look, sized to its tile by TileDecorations, not a thing on the hex.
            log.info("FOOTPRINT %s a tile's decoration: the tile's own look" % model)
            continue
        if world_scale.clip_library(os.path.join(HERE, model + ".py")):
            # Its stand-in rig has no body: the clips' root motion alone isn't a reach.
            log.info("FOOTPRINT %s a clip library: no body to measure" % model)
            continue
        fps, _loops = imported.settings(glb)
        lines = measure(model, glb, fps, scripts)
        if lines is None:
            log.info("FOOTPRINT %s no view puts it on the board: an item's picture" % model)
            continue
        for line, tag in lines:
            text, fails = known.judge(KNOWN, model, line)
            passed = passed and not fails
            if fails:
                log.error("FOOTPRINT %s%s %s" % (model, tag, text), glb)
            else:
                log.info("FOOTPRINT %s%s %s" % (model, tag, text))
    log.info("FOOTPRINT CHECK: %s" % ("PASS" if passed and glbs else "FAIL"))
    sys.exit(0 if passed and glbs else 1)


main()
