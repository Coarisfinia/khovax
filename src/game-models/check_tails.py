"""Checks that a beast of many tails has every one of them rigged (the owner, on #1771: "only two
are rigged"): found on the mesh, not the bones, each moved by bones of its own, a bend of them moving
only that tail, and moving in every clip (lib/tails.py).

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/check_tails.py -- <model.glb> [<model.glb> ...]

It prints a line per tail and clip and `TAILS CHECK: PASS` or `FAIL` (and exits 1 on a fail), through
game_shared.log (#1115): a failing line is an error on the .glb. A model not in TAILS passes, so CI
runs it on every .glb, and an entry whose model isn't there fails every run (#2373), so a renamed
beast can't turn the check off. A beast of many tails joins TAILS when it's imported. Blender's
modules load only once a listed beast is checked, so test_model_lists.py runs it outside Blender."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402

GAME = os.path.join(os.path.dirname(HERE), "game")
ROOT = os.path.dirname(os.path.dirname(GAME))
# The models of many tails, from the game's folder, and how many each has.
TAILS = {"resourcepacks/default/models/kalvrakkor_magma/kalvrakkor_magma.glb": 9}


def stale():
    """How many TAILS entries name no model, each reported. It looks for the files, not git's list,
    as check_painted_eyes.py does: Blender runs in a container without git."""
    gone = [path for path in TAILS if not os.path.isfile(os.path.join(ROOT, path))]
    for path in gone:
        log.error("on TAILS, but no such model exists: take it off the list", path)
    return len(gone)


def main():
    glbs = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg.endswith(".glb")]
    passed = stale() == 0
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        path = os.path.relpath(os.path.realpath(glb), ROOT).replace(os.sep, "/")
        if path not in TAILS:
            continue
        import bpy
        from lib import tails

        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None:
            log.error("TAILS %s has no rig" % model, glb)
            passed = False
            continue
        lines, ok = tails.report(rig, bpy.data.objects, TAILS[path])
        passed = passed and ok
        for line in lines:
            if line.startswith("FAIL"):
                log.error("TAILS %s %s" % (model, line), glb)
            else:
                log.info("TAILS %s %s" % (model, line))
    verdict = "PASS" if passed and glbs else "FAIL"
    log.info("TAILS CHECK: %s" % verdict)
    sys.exit(0 if passed and glbs else 1)


if __name__ == "__main__":
    main()
