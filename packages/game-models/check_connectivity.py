"""Checks that every part attached to the skin stays on it (#1403): every frame of every clip,
how far each part (a crystal, a gem, a horn, a claw, a tuft) moves off the piece it sits on,
against its gap there at rest, and how far it sinks into it (#1458), from lib/connectivity.py,
where the pieces, their anchors, the tolerance and the sink are documented. test_connectivity.py
tests it.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_connectivity.py -- <model.glb> [<model.glb> ...] [tolerance=0.005]

It prints how many parts the model has, a line per clip (the most a part lifts off its anchor and
the most one sinks into it, each with the frame, the part and its anchor, named after the bone
that moves it most) and
`CONNECTIVITY CHECK: PASS` or `FAIL` (and exits 1 on a fail), through game_shared.log (#1115): a
failing line is an error on the .glb. A model of one piece, or without a rig, passes, so CI runs
it on every .glb. The clip rate comes from the .glb's .import, as the game imports it.

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
from lib import connectivity, ground, imported, known  # noqa: E402

# (model, clip) that fails today, with the issue that fixes it; that issue takes its entries off.
KNOWN = {
    ("mana_pup", "Attack"): 1444,
    ("mana_pup", "Channel"): 1444,
    ("mana_pup", "ChannelEnd"): 1444,
    ("mana_pup", "ChannelStart"): 1444,
    ("mana_pup", "Faint"): 1444,
    ("mana_pup", "Feed"): 1444,
    ("mana_pup", "Hit"): 1444,
    ("mana_pup", "Idle"): 1444,
    ("mana_pup", "Sleep"): 1444,
    ("mana_wolf", "Faint"): 1445,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glbs = [arg for arg in args if arg.endswith(".glb")]
    rest = [arg for arg in args if not arg.endswith(".glb")]
    tolerance = float(rest[0]) if rest else connectivity.TOLERANCE
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        fps, _loops = imported.settings(glb)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None or rig.animation_data is None:
            # A prop: no rig, no clips, nothing moves off anything.
            lines = ["no rig: nothing to check"]
        else:
            rig.animation_data.use_nla = False
            lines, _passed = connectivity.report(rig, ground.skinned(bpy.data.objects), tolerance)
        for line in lines:
            text, fails = known.judge(KNOWN, model, line)
            passed = passed and not fails
            if fails:
                log.error("CONNECTIVITY %s %s" % (model, text), glb)
            else:
                log.info("CONNECTIVITY %s %s" % (model, text))
        # A KNOWN entry no clip line judged (a model of one piece, a clip renamed or gone) can't
        # pass, so it would stay listed forever: it fails until it's taken off.
        judged = {line.split(" ", 2)[1].rstrip(":") for line in lines if line.split(" ", 1)[0] in ("ok", "FAIL")}
        for (name, clip), issue in sorted(KNOWN.items()):
            if name == model and clip not in judged:
                passed = False
                log.error("CONNECTIVITY %s FAIL %s, which KNOWN still lists (#%d), wasn't checked: take it off" % (
                    model, clip, issue), glb)
    log.info("CONNECTIVITY CHECK: %s (tolerance %.1f mm)" % ("PASS" if passed and glbs else "FAIL", tolerance * 1000))
    sys.exit(0 if passed and glbs else 1)


main()
