"""Turns a take from a motion capture database (ASF/AMC, the CMU database's, #1951) into a clip source
of the player's clip library (#1935): the take's frames from `first` to `last`, retargeted onto the
library's skeleton (lib/mocap.py) and written like import_clip.py's clip sources.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/import_mocap.py -- <take.asf> <take.amc> <first> <last> <Clip> \
        packages/game-models/sources/player/clips/<Clip>.glb

`first` and `last` are the take's own frame numbers (it's captured at `CAPTURED` frames a second,
sampled down to the clip rate). The raw take stays out of the repository, beside the owner's Meshy
exports in khovax-sources; its source and licence go into the library's SOURCE.md."""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import clip_sources, mocap, scene  # noqa: E402

# The CMU database captures at 120 frames a second.
CAPTURED = 120
SKELETON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources", "player", "skeleton.glb")
# The library's bones (Meshy's Mixamo names), each with the capture bone it follows.
BONES = {
    "mixamorig:Hips": "root",
    "mixamorig:Spine": "lowerback",
    "mixamorig:Spine1": "upperback",
    "mixamorig:Spine2": "thorax",
    "mixamorig:Neck": "lowerneck",
    "mixamorig:Head": "head",
}
for side, short in (("Left", "l"), ("Right", "r")):
    BONES.update({
        "mixamorig:%sShoulder" % side: short + "clavicle",
        "mixamorig:%sArm" % side: short + "humerus",
        "mixamorig:%sForeArm" % side: short + "radius",
        "mixamorig:%sHand" % side: short + "hand",
        "mixamorig:%sUpLeg" % side: short + "femur",
        "mixamorig:%sLeg" % side: short + "tibia",
        "mixamorig:%sFoot" % side: short + "foot",
        "mixamorig:%sToeBase" % side: short + "toes",
    })

args = sys.argv[sys.argv.index("--") + 1:]
if len(args) != 6:
    sys.exit("usage: -- <take.asf> <take.amc> <first> <last> <Clip> <clip-source.glb>")
asf, amc, first, last, clip, out = args
skeleton = mocap.Skeleton(asf)
frames = mocap.read_motion(amc)[int(first) - 1:int(last)]
if not frames:
    sys.exit("no frames from %s to %s in %s" % (first, last, amc))
scene.reset(clip_sources.FPS)
rig, _ = clip_sources.load(SKELETON)
rig.animation_data_create()
action = bpy.data.actions.new(clip)
rig.animation_data.action = action
keyed = mocap.retarget(skeleton, frames, rig, BONES, CAPTURED // clip_sources.FPS)
rig.animation_data.action = None
clip_sources.stash(rig, action, clip)
clip_sources.write(rig, out)
print("MOCAP %s: frames %s-%s of %s, %d keyed" % (clip, first, last, os.path.basename(amc), keyed))
