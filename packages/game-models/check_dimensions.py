"""Checks that every model's limbs have sane dimensions (the owner, on #1297): each limb's segments
against each other and against how high the body stands, at rest, per body plan, from
lib/dimensions.py, where the measures and their ranges are documented.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_dimensions.py -- <model.glb> [<model.glb> ...]

It prints a line per measure (its value and its range) and `DIMENSIONS CHECK: PASS` or `FAIL` (and
exits 1 on a fail), through game_shared.log (#1115): a failing line is an error on the .glb. A
model without a rig, or without limbs of a known body plan, passes, so CI runs it on every .glb."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import dimensions  # noqa: E402


def main():
    glbs = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg.endswith(".glb")]
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None:
            # A prop: no rig, so no limbs.
            log.info("DIMENSIONS %s no rig: nothing to check" % model)
            continue
        lines, ok = dimensions.report(rig)
        passed = passed and ok
        for line in lines:
            if line.startswith("FAIL"):
                log.error("DIMENSIONS %s %s" % (model, line), glb)
            else:
                log.info("DIMENSIONS %s %s" % (model, line))
    verdict = "PASS" if passed and glbs else "FAIL"
    log.info("DIMENSIONS CHECK: %s" % verdict)
    sys.exit(0 if passed and glbs else 1)


main()
