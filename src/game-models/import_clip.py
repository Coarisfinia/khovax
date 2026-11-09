"""Turns one of Meshy's rigged exports into a clip source (#1935): its rig and its one clip, without
the body (lib/clip_sources.py), which a clip library's script merges with the others.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/import_clip.py -- <export.glb> <Clip> <clip-source.glb>

Meshy rigs one clip per export (#1934): the owner exports each clip from the same rigged body, and
each becomes its own clip source, named after the clip the game plays (`Wave`), in the library's
`clips/` folder (sources/player/clips/Wave.glb). `rest` instead of a clip name keeps only the rig at
rest: the library's skeleton (sources/player/skeleton.glb), which every clip must share. The
library's build checks that they do (lib/skeleton.py) and fails naming what differs."""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import clip_sources, scene  # noqa: E402

REST = "rest"

args = sys.argv[sys.argv.index("--") + 1:]
if len(args) != 3:
    sys.exit("usage: -- <export.glb> <Clip|rest> <clip-source.glb>")
export, clip, source = args
scene.reset(clip_sources.FPS)
rig, action = clip_sources.load(export)
if clip != REST:
    if action is None:
        sys.exit("%s has no clip" % export)
    clip_sources.stash(rig, action, clip)
elif action is not None:
    action.use_fake_user = False
    rig.animation_data_clear()
    bpy.data.actions.remove(action)
clip_sources.write(rig, source)
print("CLIP SOURCE %s: %d bones, %s" % (source, len(rig.data.bones), "rest" if clip == REST else "clip " + clip))
