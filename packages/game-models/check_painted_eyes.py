"""Checks that no generator's eye area is left in a creature's texture (#1688): on the head of
each creature model, neither a flat black oval nor a painted glowing eye, next to or under our own
(check_eyes.py checks those are there). It samples the texture over the head's faces and looks
for a mirrored pair as lib/marked_eyes.py's `find` does on import, with `DARK` and with `GLOW`.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_painted_eyes.py -- <model.glb> [<model.glb> ...]

A model without a rig, a creature check_clip_set.py's NOT_CREATURES leaves out (the tentacle
gate's eye is part of its design, #1642), and a skin without a texture or a head bone pass: nothing
painted there. A beast still waiting for our eyes is in KNOWN with the issue that gives them; it
doesn't fail, and fails once it passes until it's taken off (lib/known.py's way). It prints a line
per model and `PAINTED EYES CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb. CI runs it on every .glb."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from check_clip_set import NOT_CREATURES  # noqa: E402
from game_shared import log  # noqa: E402
from lib import ground, marked_eyes  # noqa: E402

# The game's project folder, which NOT_CREATURES' and KNOWN's paths start from.
GAME = os.path.join(os.path.dirname(HERE), "game")

# Beasts whose texture still shows the generator's eyes, each with the issue that gives them ours.
# Fohossa's and the Frostfire Hound's painted eyes are neither `DARK` nor `GLOW`, so the check
# doesn't see them yet (#1719).
KNOWN = {
    "assets/drakkudor/drakkudor.glb": "#1684",
}


def found(objects):
    """What the generator left on the head of each skin among `objects`: a line per mirrored pair
    of marked spots, with where they are and how wide."""
    lines = []
    for skin in ground.skinned(objects):
        for kind, marks in marked_eyes.painted(skin).items():
            lines.append("%s: %s eyes at %s and %s, %.3f and %.3f wide" % (
                skin.name, kind, tuple(round(float(v), 3) for v in marks[0].middle),
                tuple(round(float(v), 3) for v in marks[1].middle), marks[0].width, marks[1].width))
    return lines


def main():
    glbs = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg.endswith(".glb")]
    failed = 0
    for glb in glbs:
        path = os.path.relpath(os.path.abspath(glb), GAME).replace(os.sep, "/")
        if path in NOT_CREATURES:
            log.info("PAINTED EYES %s: not a creature (%s)" % (path, NOT_CREATURES[path]))
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        lines = found(bpy.data.objects)
        if path in KNOWN:
            if lines:
                log.info("PAINTED EYES %s: %s, known (%s)" % (path, "; ".join(lines), KNOWN[path]))
            else:
                failed += 1
                log.error("PAINTED EYES no generated eyes left: take it off KNOWN (%s)" % KNOWN[path], glb)
        elif lines:
            failed += 1
            log.error("PAINTED EYES %s: paint them over with lib/marked_eyes.py's `replace`" % "; ".join(lines), glb)
        else:
            log.info("PAINTED EYES %s: no generated eyes on the head" % path)
    verdict = "PASS" if glbs and not failed else "FAIL"
    log.info("PAINTED EYES CHECK: %s" % verdict)
    sys.exit(0 if verdict == "PASS" else 1)


main()
