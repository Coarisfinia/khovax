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
(#1641). Two kinds aren't things standing on a hex and are left out by what they are: a tile's
decoration (a model a tile blueprint names), which is the tile's own look (the owner, on #1651),
and a pack's model, which has no script here and is sized by the view that shows it (#1652). So CI
runs it on every .glb.
The clip rate comes from the .glb's .import, as the game imports it.

A clip that still fails today waits in KNOWN with the issue that fixes it: it prints its numbers
and doesn't fail the check. The list only shrinks: a clip on it that passes fails the check
until it's taken off."""

import glob
import os
import re
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import footprint, imported, known  # noqa: E402

# The tile blueprints, whose `model` is the tile's decoration (TileDecorations shows it).
TILES = os.path.join(os.path.dirname(HERE), "game", "core", "data", "tiles", "*.jsonc")

# The models (by .glb name) of bosses, enraged or stronger monsters, which may reach past their hex.
LARGE = {"fohossa"}

# (model, clip or "rest" for the rest pose) that fails today, with the issue that fixes it; that
# issue takes its entries off.
KNOWN = {
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


def decorations():
    """The names of the models the tile blueprints name as their decoration."""
    names = set()
    for path in glob.glob(TILES):
        with open(path, encoding="utf-8") as text:
            for found in re.finditer(r'"model"\s*:\s*"([^"]+)"', text.read()):
                names.add(os.path.splitext(os.path.basename(found.group(1)))[0])
    if not names:
        sys.exit("no tile blueprint names a model in %s: the path moved?" % TILES)
    return names


def main():
    glbs = sys.argv[sys.argv.index("--") + 1:]
    tile_looks = decorations()
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        if model in tile_looks:
            # The tile's own look, sized to its tile by TileDecorations, not a thing on the hex.
            log.info("FOOTPRINT %s a tile's decoration: the tile's own look" % model)
            continue
        if not os.path.exists(os.path.join(HERE, model + ".py")):
            # A pack's model (the players' and people's figures, the chest) has no script here: the
            # view that shows it sets its size.
            log.info("FOOTPRINT %s no model script: a pack's model, sized by its view" % model)
            continue
        fps, _loops = imported.settings(glb)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is not None and rig.animation_data is not None:
            rig.animation_data.use_nla = False
        limits = footprint.limits(rig, model in LARGE)
        lines, _passed = footprint.report(rig, footprint.meshes(rig, bpy.data.objects), limits)
        for line in lines:
            text, fails = known.judge(KNOWN, model, line)
            passed = passed and not fails
            if fails:
                log.error("FOOTPRINT %s %s" % (model, text), glb)
            else:
                log.info("FOOTPRINT %s %s" % (model, text))
    log.info("FOOTPRINT CHECK: %s" % ("PASS" if passed and glbs else "FAIL"))
    sys.exit(0 if passed and glbs else 1)


main()
