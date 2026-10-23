"""Checks that no eye shows above its brow (the owner, on #1249): at rest and every other frame
of every clip, each eye seen from the model's front, from its side and straight into it, from
lib/brows.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_brows.py -- <model.glb> [<model.glb> ...] [tolerance=0.0025]

It fails when more of an eye than the tolerance (a share of the eye's disc) shows above a brow
(or any surface lying on the eye) crossing it: a brow may overlap the eye, but the eye's top must
not shine through above it. It prints a line for the rest pose and each clip: how much of the eye
shows, the frame, the eye and the view, and `BROW CHECK: PASS` or `FAIL` (and exits 1 on a fail),
through game_shared.log (#1115): a failing line is an error on the .glb. A model without eye
points passes, so CI runs it on every .glb."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import brows, ground, imported  # noqa: E402


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glbs = [arg for arg in args if arg.endswith(".glb")]
    rest = [arg for arg in args if not arg.endswith(".glb")]
    tolerance = float(rest[0]) if rest else 0.0025
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        fps, _loops = imported.settings(glb)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None:
            # A prop: no rig, so no eye points.
            log.info("BROW %s no rig: nothing to check" % model)
            continue
        if rig.animation_data is not None:
            rig.animation_data.use_nla = False
        lines, ok = brows.report(rig, ground.skinned(bpy.data.objects), tolerance)
        passed = passed and ok
        for line in lines:
            if line.startswith("FAIL"):
                log.error("BROW %s %s" % (model, line), glb)
            else:
                log.info("BROW %s %s" % (model, line))
    verdict = "PASS" if passed and glbs else "FAIL"
    log.info("BROW CHECK: %s (tolerance %.2f %% of the eye)" % (verdict, tolerance * 100))
    sys.exit(0 if passed and glbs else 1)


main()
