"""Checks that a beast of many tails has every one of them rigged (the owner, on #1771: "only two
are rigged"): found on the mesh, not the bones, each moved by bones of its own, a bend of them moving
only that tail, and moving in every clip (lib/tails.py).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_tails.py -- <model.glb> [<model.glb> ...]

It prints a line per tail and clip and `TAILS CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb. A model not in TAILS passes, so CI
runs it on every .glb. A beast of many tails joins TAILS when it's imported."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import tails  # noqa: E402

# The models (by .glb name) of many tails, and how many each has.
TAILS = {"kalvrakkor_magma": 9}


def main():
    glbs = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg.endswith(".glb")]
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        if model not in TAILS:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None:
            log.error("TAILS %s has no rig" % model, glb)
            passed = False
            continue
        lines, ok = tails.report(rig, bpy.data.objects, TAILS[model])
        passed = passed and ok
        for line in lines:
            if line.startswith("FAIL"):
                log.error("TAILS %s %s" % (model, line), glb)
            else:
                log.info("TAILS %s %s" % (model, line))
    verdict = "PASS" if passed and glbs else "FAIL"
    log.info("TAILS CHECK: %s" % verdict)
    sys.exit(0 if passed and glbs else 1)


main()
