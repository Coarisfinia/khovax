"""Checks that a model's clips move cleanly (model skill, #1071): per clip, foot sliding, the loop
seam and jitter, as numbers with limits that fail the build.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/check_motion.py -- \
        <model.glb> [<Clip>=<speed> ...]

- **Foot sliding:** how fast a paw moves over the ground while it stands on it (its lowest point
  within CONTACT of the ground), in metres a second. The ground runs back under the model at the
  speed the game moves it while it plays the clip (`Walk=2.17`, metres a second; none given is
  standing still). The limit holds for every clip: the legs plant their paws (#1073).
- **Loop seam** (the clips the model's .import loops): how far the last frame's pose is from the
  first's (degrees, and the root's shift in millimetres), and how rough the curves run through
  it (below). A loop that eases to a stop at its ends shows here.
- **Jitter:** how rough a joint's curve runs: how much its change of speed from one frame to the
  next (the second difference of its angle, degrees a frame per frame) departs from the frames
  either side, at the roughest frame of any joint, across the seam too on a loop. A fast move
  that bends smoothly passes; a pop, a snap or a stall doesn't.

- **Joins** (#1158): a loop played between a lead-in and a lead-out, named after it (`Channel`
  between `ChannelStart` and `ChannelEnd`): how far the lead-in's last pose is from the loop's
  first, and the loop's first from the lead-out's first, under the seam's limits, so the game
  can hand over from one to the next at any loop's end.
- **Start:** a clip must start at time 0; Godot holds a late first key from 0 until then, a
  pause at every loop's seam.

It prints a line per clip and `MOTION CHECK: PASS` or `FAIL` (and exits 1 on a fail). The clip
rate and the loops come from the .glb's .import, as the game imports it."""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import ground, imported  # noqa: E402

# A paw this close to the ground (metres) stands on it.
CONTACT = 0.02
# The limits: paw speed over the ground (m/s), the seam's pose (degrees) and root shift
# (metres), and how rough a curve may run anywhere, the seam included (degrees a frame per frame,
# see roughness).
SLIDE_LIMIT = 0.2
SEAM_POSE_LIMIT = 0.5
SEAM_ROOT_LIMIT = 0.002
JITTER_LIMIT = 15.0


def spin(a, b):
    """The rotation from quaternion `a` to `b`, as a vector in degrees (axis times angle)."""
    turn = a.rotation_difference(b)
    if turn.w < 0.0:
        turn.negate()
    axis, angle = turn.to_axis_angle()
    return axis * math.degrees(angle)


def sample(rig, meshes, feet, start, end):
    """Every frame's local bone rotations, root shift and, per foot, its lowest point and centre."""
    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    parts = {obj.name: ground.owned(obj, feet) for obj in meshes}
    frames = []
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        turns = {bone.name: bone.matrix_basis.to_quaternion() for bone in rig.pose.bones}
        root = next(bone for bone in rig.pose.bones if bone.parent is None).location.copy()
        points = {name: [] for name in feet}
        for obj in meshes:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            world = evaluated.matrix_world
            for name, indices in parts[obj.name].items():
                points[name] += [world @ mesh.vertices[index].co for index in indices]
            evaluated.to_mesh_clear()
        # A foot may be split over several meshes: all of its parts count.
        spots = {}
        for name, found in points.items():
            if found:
                centre = sum(found, found[0] * 0.0) / len(found)
                spots[name] = (min(point.z for point in found), centre.x, centre.y)
        frames.append((turns, root, spots))
    return frames


def standing(height):
    """On the ground: within CONTACT of it (a paw sunk deeper is the ground check's failure)."""
    return -CONTACT < height < CONTACT


def sliding(frames, feet, fps, speed):
    """The fastest and the mean paw speed over the ground while standing, and each paw's fastest.
    The model faces -Y, so the ground runs toward +Y under it."""
    fastest = {name: 0.0 for name in feet}
    speeds = []
    for (_t0, _r0, now), (_t1, _r1, after) in zip(frames, frames[1:]):
        for name in feet:
            if name in now and name in after and standing(now[name][0]) and standing(after[name][0]):
                dx = (after[name][1] - now[name][1]) * fps
                dy = (after[name][2] - now[name][2]) * fps - speed
                slide = math.hypot(dx, dy)
                speeds.append(slide)
                fastest[name] = max(fastest[name], slide)
    mean = sum(speeds) / len(speeds) if speeds else 0.0
    return max(speeds, default=0.0), mean, fastest


def spins(frames):
    """Per bone, its rotation from each frame to the next (the last frame of a loop is its first)."""
    bones = frames[0][0].keys()
    return {bone: [spin(a[0][bone], b[0][bone]) for a, b in zip(frames, frames[1:])] for bone in bones}


def roughness(turns, loop):
    """Per bone, how much each frame's change of speed (the second difference of its angle)
    departs from the frames either side, by frame: a curve that bends smoothly changes its speed
    smoothly, while a pop, a snap or a stall stands out. A loop wraps around its seam."""
    out = {}
    for bone, steps in turns.items():
        if loop:
            steps = steps[-2:] + steps + steps[:2]
        bends = [after - before for before, after in zip(steps, steps[1:])]
        rough = [(bend - (before + after) / 2).length for before, bend, after in zip(bends, bends[1:], bends[2:])]
        out[bone] = rough if loop else [0.0, 0.0] + rough + [0.0, 0.0]
    return out


def jitter(rough, start):
    """The roughest frame of any joint: (degrees a frame per frame, bone, frame)."""
    return max(((value, bone, start + index) for bone, values in rough.items() for index, value in enumerate(values)),
               default=(0.0, "", start))


def seam(frames, rough):
    """How far a loop's last pose is from its first (degrees, root metres), and how rough its
    curves run through the seam (the first frame), with the roughest bone."""
    pose, root = apart(frames[0], frames[-1])
    speed, bone = max((values[0], bone) for bone, values in rough.items())
    return pose, root, speed, bone


def apart(a, b):
    """How far pose `b` is from pose `a`: the most any bone turns (degrees), the root's shift (metres)."""
    return max(spin(a[0][bone], b[0][bone]).length for bone in a[0]), (b[1] - a[1]).length


def joins(ends, loops):
    """Each loop's joins to its lead-in (<loop>Start) and lead-out (<loop>End), from `ends` (each
    clip's first and last frame): lines and whether they pass."""
    lines, passed = [], True
    for loop in sorted(name for name in loops if name in ends):
        first = ends[loop][0]
        pairs = []
        if loop + "Start" in ends:
            pairs.append((loop + "Start", ends[loop + "Start"][1], first))
        if loop + "End" in ends:
            pairs.append((loop + "End", first, ends[loop + "End"][0]))
        for lead, before, after in pairs:
            pose, root = apart(before, after)
            fails = pose > SEAM_POSE_LIMIT or root > SEAM_ROOT_LIMIT
            passed = passed and not fails
            lines.append("%s %s join: %.2f deg, root %.1f mm" % ("FAIL" if fails else "ok", lead, pose, root * 1000))
    return lines, passed


def check(rig, meshes, fps, loops, speeds):
    feet = ground.foot_bones(rig)
    lines, passed, ends = [], True, {}
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        start, end = imported.play(rig, action)
        # A clip that starts after time 0 holds its first pose until then in the game: a pause
        # at every loop's seam (#1089).
        late = start != 0
        loop = action.name in loops
        frames = sample(rig, meshes, feet, start, end)
        ends[action.name] = (frames[0], frames[-1])
        slide, mean, fastest = sliding(frames, feet, fps, speeds.get(action.name, 0.0))
        rough = roughness(spins(frames), loop)
        shake, shaking, at = jitter(rough, start)
        fails = late or shake > JITTER_LIMIT or slide > SLIDE_LIMIT
        text = "slide %.2f m/s (mean %.2f; %s)" % (
            slide, mean, ", ".join("%s %.2f" % (name, value) for name, value in sorted(fastest.items())))
        if loop:
            pose, root, speed, jumping = seam(frames, rough)
            fails = fails or pose > SEAM_POSE_LIMIT or root > SEAM_ROOT_LIMIT
            text += "; seam %.2f deg, root %.1f mm, rough %.2f deg/frame^2 (%s)" % (
                pose, root * 1000, speed, jumping)
        text += "; jitter %.2f deg/frame^2 (%s, frame %d)" % (shake, shaking, at)
        if late:
            text += "; starts at frame %d, not 0: the game holds its first pose until then" % start
        passed = passed and not fails
        lines.append("%s %s%s: %s" % ("FAIL" if fails else "ok", action.name, " (loop)" if loop else "", text))
    joined, joins_pass = joins(ends, loops)
    return lines + joined, passed and joins_pass


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glb = args[0]
    speeds = {name: float(value) for name, value in (arg.split("=", 1) for arg in args[1:])}
    fps, loops = imported.settings(glb)
    rig = imported.load(glb, fps)
    lines, passed = check(rig, ground.skinned(bpy.data.objects), fps, loops, speeds)
    for line in lines:
        print("MOTION", line)
    print("MOTION CHECK:", "PASS" if passed else "FAIL", "(at %d fps)" % fps)
    sys.exit(0 if passed else 1)


main()
