"""Checks that no static model draws as a black blob (#2595): the stock pebble's UVs sat on its
source atlas's near-black cannonball colour, and with its metallic factor it drew black as a
tile's decoration. Any model without a rig may be named as a tile's decoration, so each one's mean
diffuse albedo (lib/albedo.py) must reach MINIMUM.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/check_albedo.py -- <model.glb> [<model.glb> ...]

It prints a line per model and `ALBEDO CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb. A model with a rig (a monster, the
players' figure) is never a decoration and is passed over, so CI runs it on every .glb."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import albedo  # noqa: E402

# The least mean linear luminance a static model's surface may have: the pebble had 0.024, the
# darkest stock model meant to look as it does (the leather coin pouch) about 0.04, and the stock
# rocks about 0.2.
MINIMUM = 0.03


def main():
    glbs = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg.endswith(".glb")]
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        if any(obj.type == "ARMATURE" for obj in bpy.data.objects):
            log.info("ALBEDO %s has a rig: never a decoration" % model)
            continue
        value = albedo.mean(bpy.data.objects)
        if value is None:
            log.info("ALBEDO %s has no faces" % model)
        elif value < MINIMUM:
            passed = False
            log.error("ALBEDO %s FAIL %.3f, below %.3f: it draws black" % (model, value, MINIMUM), glb)
        else:
            log.info("ALBEDO %s %.3f" % (model, value))
    verdict = "PASS" if passed and glbs else "FAIL"
    log.info("ALBEDO CHECK: %s (at least %.3f)" % (verdict, MINIMUM))
    sys.exit(0 if passed and glbs else 1)


main()
