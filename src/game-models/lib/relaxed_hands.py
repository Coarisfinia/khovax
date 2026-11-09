"""Relaxed, moving hands for the player's clips (#2160). The rig has no finger bones and the body's
hands are mittens, so the wrist is all a hand can move with. Meshy's clips hold it bent far off the
forearm for the whole clip, which reads as a cramped hand.

`relax` takes that held bend out of a clip's hands, keeping a little of it as a resting bend and
most of the clip's own wrist motion around it, and adds a slow sway so that a hand the clip holds
still moves too."""

import math

from mathutils import Quaternion

from lib import clip_smooth

# Each hand's bone, and where in its sway it starts, so the two hands don't move in step.
HANDS = {"mixamorig:LeftHand": 0.0, "mixamorig:RightHand": math.pi / 2.0}
# How much of the clip's held bend stays, as the hand's resting bend.
KEPT_BEND = 0.2
# How much of the clip's own wrist motion around that stays: at full size, a wrist that swings
# far in a clip bends as far as the held bend did.
KEPT_MOTION = 0.7
SWAY_DEGREES = 5.0
# About how long one sway takes, in frames. A clip holds a whole number of them, so a loop meets
# itself.
SWAY_FRAMES = 60


def _held_bend(turns):
    """The average of `turns`, which `relax` has kept each next to the last."""
    total = Quaternion((0.0, 0.0, 0.0, 0.0))
    for turn in turns:
        total += turn
    return total.normalized()


def relax(action):
    """Relaxes both hands of `action`, keying them on every frame."""
    found = clip_smooth.action_curves(action)
    first, last = (int(round(frame)) for frame in action.frame_range)
    frames = range(first, last + 1)
    sways = max(1, round((last - first) / SWAY_FRAMES))
    for bone, phase in HANDS.items():
        path = 'pose.bones["%s"].rotation_quaternion' % bone
        curves = [found[(path, index)] for index in range(4)]
        turns = [Quaternion([curve.evaluate(frame) for curve in curves]) for frame in frames]
        for index in range(1, len(turns)):
            if turns[index].dot(turns[index - 1]) < 0.0:
                turns[index].negate()
        held = _held_bend(turns)
        resting = Quaternion().slerp(held, KEPT_BEND)
        for index, curve in enumerate(curves):
            curve.keyframe_points.clear()
            curve.keyframe_points.add(len(turns))
        for slot, (frame, turn) in enumerate(zip(frames, turns)):
            along = 2.0 * math.pi * sways * (frame - first) / (last - first)
            sway = Quaternion(held.axis, math.radians(SWAY_DEGREES) * math.sin(along + phase))
            motion = Quaternion().slerp(held.inverted() @ turn, KEPT_MOTION)
            relaxed = (resting @ sway @ motion).normalized()
            for index, curve in enumerate(curves):
                point = curve.keyframe_points[slot]
                point.co = (frame, relaxed[index])
                point.interpolation = "LINEAR"
        for curve in curves:
            curve.update()
