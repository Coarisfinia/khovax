"""Checks that no body surface covers our eyes (the owner, on #1747 and #1758): at rest and every
other frame of every clip, each eye looked at straight on, from lib/covered.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_eyes_covered.py -- <model.glb> [<model.glb> ...] [tolerance=0.01]

It fails when the body (any surface but the eye's own pieces: its eyeball, iris, pupil, rim, brow
and lid) covers more of an eye's face than the tolerance (a share of the face within its rim),
poking through it or lying in front of it, its shut lid included. It prints a line for the rest
pose and each clip: how much of the eye the body covers, the frame, the eye and where up the eye,
and `EYES COVERED CHECK: PASS` or `FAIL` (and exits 1 on a fail), through game_shared.log
(#1115): a failing line is an error on the .glb. A model without eye points passes, so CI runs it
on every .glb.

A model whose eyes the body still covers today waits in KNOWN with the issue that fixes it: it
prints its numbers and doesn't fail the check. The list only shrinks: a model on it that passes
fails the check until it's taken off."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import covered, ground, imported  # noqa: E402

# Models whose eyes the body still covers, with the issue that fixes them; that issue takes them off.
KNOWN = {
    "kavrikka": 1818,
    "mana_pup": 1818,
    "mana_wolf": 1818,
    "nuvvoluvvo": 1818,
    "ombulumo": 1818,
    "ombuwomo": 1818,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glbs = [arg for arg in args if arg.endswith(".glb")]
    rest = [arg for arg in args if not arg.endswith(".glb")]
    tolerance = float(rest[0]) if rest else 0.01
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
            log.info("COVERED %s no rig: nothing to check" % model)
            continue
        if rig.animation_data is not None:
            rig.animation_data.use_nla = False
        lines, ok = covered.report(rig, ground.skinned(bpy.data.objects), tolerance)
        if model in KNOWN:
            lines = ["known %s (#%d)" % (line, KNOWN[model]) for line in lines]
            if ok:
                lines.append("FAIL its eyes are clear, yet KNOWN still lists it (#%d): take it off" % KNOWN[model])
            ok = not ok
        passed = passed and ok
        for line in lines:
            if line.startswith("FAIL"):
                log.error("COVERED %s %s" % (model, line), glb)
            else:
                log.info("COVERED %s %s" % (model, line))
    verdict = "PASS" if passed and glbs else "FAIL"
    log.info("EYES COVERED CHECK: %s (tolerance %.2f %% of the eye)" % (verdict, tolerance * 100))
    sys.exit(0 if passed and glbs else 1)


main()
