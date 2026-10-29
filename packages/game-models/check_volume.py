"""Checks that the body keeps its volume where the spine and neck bend (#1306): every frame of
every clip, the depth and width of the body's cross section at stations along the spine and
neck against their rest values, from lib/volume.py, where the stations and the share they must
keep (SHARE) are documented.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_volume.py -- <model.glb> [<model.glb> ...] [share=0.8]

It prints each station's rest depth and width, a line per clip (the smallest share of rest any
station keeps, the frame, the station and which measure), and `VOLUME CHECK: PASS` or `FAIL` (and
exits 1 on a fail), through game_shared.log (#1115): a failing line is an error on the .glb. A
model without spine or neck bones passes, so CI runs it on every .glb. The clip rate comes from
the .glb's .import, as the game imports it.

A clip that still fails today waits in KNOWN with the issue that fixes it: it prints its numbers
and doesn't fail the check. The list only shrinks: a clip on it that passes fails the check
until it's taken off. KNOWN holds at the default share only: a custom share judges every clip
as it is."""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
# Blender's own Python runs this, outside the uv environment: game_shared comes from its folder.
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "game-shared"))

from game_shared import log  # noqa: E402
from lib import ground, imported, known, volume  # noqa: E402

# (model, clip) that fails today, with the issue that fixes it; that issue takes its entries off.
KNOWN = {
    ("fohossa", "Attack"): 1628,
    ("fohossa", "Faint"): 1628,
    ("fohossa", "Feed"): 1628,
    ("fohossa", "Run"): 1628,
    ("fohossa", "Sleep"): 1628,
    ("frostfire_hound", "Attack"): 1680,
    ("frostfire_hound", "ChannelStart"): 1680,
    ("frostfire_hound", "Faint"): 1680,
    ("frostfire_hound", "Hit"): 1680,
    ("kavrikka", "Attack"): 1761,
    ("kavrikka", "Run"): 1761,
    ("nuvvoluvvo", "RollOver"): 1729,
    ("nuvvoluvvo", "Sleep"): 1729,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glbs = [arg for arg in args if arg.endswith(".glb")]
    rest = [arg for arg in args if not arg.endswith(".glb")]
    share = float(rest[0]) if rest else volume.SHARE
    # The known failures were measured at the default share; another share judges every clip.
    waiting = KNOWN if share == volume.SHARE else {}
    passed = True
    for glb in glbs:
        model = os.path.splitext(os.path.basename(glb))[0]
        fps, _loops = imported.settings(glb)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=glb)
        rig = next((obj for obj in bpy.data.objects if obj.type == "ARMATURE"), None)
        if rig is None or rig.animation_data is None:
            # A prop: no rig, no clips, no spine.
            log.info("VOLUME %s no rig: nothing to check" % model)
            continue
        rig.animation_data.use_nla = False
        lines, _passed = volume.report(rig, ground.skinned(bpy.data.objects), share)
        for line in lines:
            text, fails = known.judge(waiting, model, line)
            passed = passed and not fails
            if fails:
                log.error("VOLUME %s %s" % (model, text), glb)
            else:
                log.info("VOLUME %s %s" % (model, text))
    log.info("VOLUME CHECK: %s (share %.0f%%)" % ("PASS" if passed and glbs else "FAIL", share * 100))
    sys.exit(0 if passed and glbs else 1)


main()
