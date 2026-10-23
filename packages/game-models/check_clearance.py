"""Checks that no wisp cuts into the body (#1227): every frame of every clip, the smallest gap
between each wisp (the part of the mesh a `wisp.*` bone moves most, lib/wisps.py) and the rest of
the mesh, from lib/clearance.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_clearance.py -- <model.glb> [<model.glb> ...] [tolerance=0.005]

It fails when a wisp's faces cross the body's (or a wisp sits inside it), or when the gap falls
below the tolerance (metres, the .glb's: the game's). It prints a line per clip, its smallest
gap, the frame and the wisp and body bone it's between, and `CLEARANCE CHECK: PASS` or `FAIL`
(and exits 1 on a fail), through game_shared.log (#1115): a failing line is an error on the .glb.
A model without wisps passes, so CI runs it on every .glb. The clip rate comes from the .glb's
.import, as the game imports it.

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
from lib import clearance, ground, imported  # noqa: E402

# (model, clip) that fails today, with the issue that fixes it.
KNOWN = {
    ("mana_wolf", "Hit"): 1241,
    ("mana_wolf", "Idle"): 1241,
    ("mana_wolf", "Run"): 1241,
    ("mana_wolf", "Walk"): 1241,
}


def judge(model, line):
    """The line as reported, and whether it fails the check: a known failure doesn't, and a known
    one that passes does."""
    verdict, clip = line.split(" ", 2)[:2]
    issue = KNOWN.get((model, clip.rstrip(":")))
    if issue is None:
        return line, verdict == "FAIL"
    if verdict == "FAIL":
        return "known %s (#%d)" % (line, issue), False
    return "FAIL %s, which KNOWN still lists (#%d): take it off" % (line, issue), True


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glbs = [arg for arg in args if arg.endswith(".glb")]
    rest = [arg for arg in args if not arg.endswith(".glb")]
    tolerance = float(rest[0]) if rest else 0.005
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        fps, _loops = imported.settings(glb)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None or rig.animation_data is None:
            # A prop: no rig, no clips, no wisps.
            log.info("CLEARANCE %s no rig: nothing to check" % model)
            continue
        rig.animation_data.use_nla = False
        lines, _passed = clearance.report(rig, ground.skinned(bpy.data.objects), tolerance)
        for line in lines:
            text, fails = judge(model, line)
            passed = passed and not fails
            if fails:
                log.error("CLEARANCE %s %s" % (model, text), glb)
            else:
                log.info("CLEARANCE %s %s" % (model, text))
    log.info("CLEARANCE CHECK: %s (tolerance %.1f mm)" % ("PASS" if passed and glbs else "FAIL", tolerance * 1000))
    sys.exit(0 if passed and glbs else 1)


main()
