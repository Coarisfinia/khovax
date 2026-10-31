"""Whether a standing clip keeps a foot planted (#1980): on every frame, one foot's toes (its toe
joint and the toe's tip) are where they are at rest, give or take `TOLERANCE`, and no toe is below
the floor. The rig stands on the floor at rest, so a toe's height above its rest height is how far
it is off the ground. A clip that floats, or stands on its heels with its toes up, fails."""

import math

import bpy
from mathutils import Matrix, Vector

TOLERANCE = 0.02
SIDES = ("Left", "Right")
# The joints of a foot's toes, per side, in Meshy's Mixamo names.
TOES = {side: ["mixamorig:%sToeBase" % side, "mixamorig:%sToe_End" % side] for side in SIDES}
HIPS = "mixamorig:Hips"
# A foot whose ankle is this close to its rest height once the body is lowered stands on the
# ground, and planting lays its sole flat.
NEAR = 0.03


def _playing(rig, action):
    """Plays `action` alone on `rig`; returns how to put back what played before."""
    data = rig.animation_data or rig.animation_data_create()
    tracks = [(track, track.mute) for track in data.nla_tracks]
    held, held_slot = data.action, data.action_slot
    for track, _ in tracks:
        track.mute = True
    data.action = action
    if action.slots:
        data.action_slot = action.slots[0]

    def restore():
        data.action = held
        if held is not None:
            data.action_slot = held_slot
        for track, mute in tracks:
            track.mute = mute
    return restore


def _frames(action):
    first, last = (int(round(frame)) for frame in action.frame_range)
    return range(first, last + 1)


def plant(rig, action):
    """Puts a standing clip's feet on the ground, keying `action` on every frame: the body is
    lowered or raised until the lower ankle is at its rest height, and every foot then that close
    to the ground lies flat, turned only about the vertical (its toes level, as at rest). Meshy's
    clips and retargeted motion capture both let the feet float or tip onto their heels (#1980)."""
    restore = _playing(rig, action)
    to_world, to_rig = rig.matrix_world.to_3x3(), rig.matrix_world.to_3x3().inverted()
    ankles = {side: "mixamorig:%sFoot" % side for side in SIDES}
    rest_z = {side: (rig.matrix_world @ rig.data.bones[ankles[side]].head_local).z for side in SIDES}
    for frame in _frames(action):
        bpy.context.scene.frame_set(frame)
        lift = {side: (rig.matrix_world @ rig.pose.bones[ankles[side]].head).z - rest_z[side] for side in SIDES}
        drop = min(lift.values())
        hips = rig.pose.bones[HIPS]
        rest = hips.bone.matrix_local.to_3x3()
        hips.location = hips.location - rest.inverted() @ (to_rig @ Vector((0.0, 0.0, drop)))
        hips.keyframe_insert("location", frame=frame)
        bpy.context.view_layer.update()
        for side in SIDES:
            if lift[side] - drop > NEAR:
                continue
            foot = rig.pose.bones[ankles[side]]
            toe = rig.pose.bones["mixamorig:%sToeBase" % side]
            flat = foot.bone.matrix_local.to_3x3()
            # How far the foot has turned about the vertical: its toes' direction across the
            # ground now against at rest.
            now = to_world @ (toe.head - foot.head)
            was = to_world @ (toe.bone.head_local - foot.bone.head_local)
            yaw = math.atan2(now.y, now.x) - math.atan2(was.y, was.x)
            turn = to_rig @ Matrix.Rotation(yaw, 3, "Z") @ to_world
            foot.matrix = Matrix.Translation(foot.head) @ (turn @ flat).to_4x4()
            bpy.context.view_layer.update()
            toe.rotation_mode = "QUATERNION"
            toe.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            foot.rotation_mode = "QUATERNION"
            foot.keyframe_insert("rotation_quaternion", frame=frame)
            toe.keyframe_insert("rotation_quaternion", frame=frame)
    restore()


def problems(rig, action):
    """What keeps `action` on `rig` from standing on the ground: one line per kind of fault, naming
    its frames and the worst height. Empty when every frame has a foot flat on the floor."""
    rests = {bone: (rig.matrix_world @ rig.data.bones[bone].head_local).z
             for joints in TOES.values() for bone in joints}
    restore = _playing(rig, action)
    lifted, sunk = [], []
    for frame in _frames(action):
        bpy.context.scene.frame_set(frame)
        heights = {bone: (rig.matrix_world @ rig.pose.bones[bone].head).z - rests[bone] for bone in rests}
        # The foot on the ground is the one whose higher toe joint is lowest.
        lowest = min(max(heights[bone] for bone in joints) for joints in TOES.values())
        if lowest > TOLERANCE:
            lifted.append((frame, lowest))
        deepest = min(heights.values())
        if deepest < -TOLERANCE:
            sunk.append((frame, deepest))
    restore()
    found = []
    if lifted:
        found.append("no foot flat on the ground on %d frames (first %d), toes up to %.3f above it"
                     % (len(lifted), lifted[0][0], max(height for _, height in lifted)))
    if sunk:
        found.append("a toe below the floor on %d frames (first %d), down to %.3f"
                     % (len(sunk), sunk[0][0], -min(height for _, height in sunk)))
    return found
