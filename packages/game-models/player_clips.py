"""The player's clips (#1935): every clip source of the baseline body (#1827) merged onto one rig, as
a clip library of its own, apart from the body. A later body loads the same clips: Godot maps the
rig's bones to its humanoid skeleton profile on import (the BoneMap in player_clips.glb.import),
so any humanoid rig, whatever its bones are called, can be retargeted to them.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/player_clips.py -- resourcepacks/default/models/player/player_clips.glb

Meshy rigs one clip per export (#1934); import_clip.py turns each into a clip source in
sources/player/clips/, named after its clip, and its skeleton into sources/player/skeleton.glb. The
build fails when a clip source's skeleton differs from it (bones, their parents, their rest pose;
lib/skeleton.py), naming each difference: a clip made on another rig would bend the body wrongly.
CI builds it with every model (check_rebuild.py), so a clip from another rig fails there."""

import glob
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import (clip_smooth, clip_sources, pace, paced_gait, planted_feet, relaxed_hands, scene, skeleton,  # noqa: E402
                 standing_feet)

# No body to size against the world (check_world_scale.py): the clips play on the stand-in rig.
WORLD_SCALE = "clip_library"
SOURCES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources", "player")
SKELETON = os.path.join(SOURCES, "skeleton.glb")
CLIPS = os.path.join(SOURCES, "clips")
# The clips the player plays standing (#1980): the build plants their feet and fails unless, on
# every frame, one foot is flat on the ground (lib/planted_feet.py). The others leave the ground on
# purpose: running, sitting, falling, getting up.
GROUNDED = ["HarvestBush", "Hit", "Idle", "PickUp", "Talk", "Throw", "Wave"]
# The clips whose source pops and snaps (the motion check's jitter, #2153): the build runs their
# curves through a Gaussian of SMOOTHING frames before it plants their feet.
SMOOTHED = ["GetUp", "HarvestBush", "Hit", "KnockedDown", "PickUp", "Throw"]
SMOOTHING = 1.0
# The clips whose motion capture lets a standing foot creep (#2154): lib/standing_feet.py holds it.
HELD = ["Hit", "KnockedDown", "PickUp", "Throw"]
# The speeds the motion check measures the gaits at (metres a second of the clips' own units,
# #2128). The game moves the player at one pace and plays the run (lib/pace.py); the walk, which it
# doesn't play, can't reach that pace and stay a walk, so it's checked at a walking pace of its own.
WALK_SPEED = 0.94
RUN_SPEED = pace.player()
# The walk loops, and pops like the one-shots: smoothed too, around its seam, then its standing
# feet held at its pace (lib/paced_gait.py).
WALK_SMOOTHING = 1.5


def mismatches(clips):
    """Every way a clip source's skeleton differs from the library's, one line each."""
    expected = skeleton.read(SKELETON)
    return ["%s: %s" % (os.path.basename(path), line)
            for path in clips for line in skeleton.differences(expected, skeleton.read(path))]


def build(out):
    clips = sorted(glob.glob(os.path.join(CLIPS, "*.glb")))
    if not clips:
        raise RuntimeError("no clip source in %s" % CLIPS)
    problems = mismatches(clips)
    for line in problems:
        print("SKELETON %s" % line)
    if problems:
        raise RuntimeError("%d clip sources don't share the skeleton (SKELETON lines)"
                           % len({line.split(":")[0] for line in problems}))
    scene.reset(clip_sources.FPS)
    rig, _ = clip_sources.load(SKELETON)
    floating = []
    for path in clips:
        other, action = clip_sources.load(path)
        if action is None:
            raise RuntimeError("%s has no clip" % path)
        name = os.path.splitext(os.path.basename(path))[0]
        if name in SMOOTHED:
            clip_smooth.smooth(rig, action, SMOOTHING)
        elif name == "Walk":
            clip_smooth.smooth(rig, action, WALK_SMOOTHING, True)
        relaxed_hands.relax(action)
        clip_sources.stash(rig, action, name)
        # Its rig was only the clip's carrier: the clip now plays on the library's.
        armature = other.data
        bpy.data.objects.remove(other, do_unlink=True)
        bpy.data.armatures.remove(armature, do_unlink=True)
        print("CLIP %s: frames %d-%d" % (name, *action.frame_range))
        if name == "Walk":
            paced_gait.pace(rig, action, WALK_SPEED, clip_sources.FPS)
        elif name in HELD:
            standing_feet.hold(rig, action, name in GROUNDED)
        elif name in GROUNDED:
            planted_feet.plant(rig, action)
        if name in GROUNDED:
            for line in planted_feet.problems(rig, action):
                print("GROUND %s: %s" % (name, line))
                floating.append(name)
    if floating:
        raise RuntimeError("standing clips off the ground (GROUND lines): %s"
                           % ", ".join(sorted(set(floating))))
    print("PLAYER CLIPS: %d clips on %d bones" % (len(clips), len(rig.data.bones)))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    clip_sources.prepare(rig)
    scene.export_glb(out)


build(sys.argv[sys.argv.index("--") + 1])
