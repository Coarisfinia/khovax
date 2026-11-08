"""A looping gait's standing feet held at its pace (#2128). The capture behind the player's walk
lets a foot creep as it lands. `pace` works on the smoothed cycle: it finds each foot's stance,
carries the ankle back at the pace through it, flat on the floor, swings it between stances on a
curve that leaves and lands at that speed, and bends the leg there with lib/standing_feet.py's IK.
The body keeps the clip's motion, lowered only as far as the standing legs need."""

import math

import bpy
from mathutils import Vector

from lib import clip_smooth, planted_feet, standing_feet as feet

# A foot stands while it's within this of its lowest (metres) and being carried back...
LOW = 0.06
# ...at no less than this share of the pace.
BACKWARD = 0.5
# The frames, at least, and the share of the cycle (one in so many frames) a foot takes either
# side of a stance to go from flat to its own turn.
BLEND = 3
FLAT_SHARE = 4
# The share of a leg's length a standing leg reaches at most: near straight, a knee bends fast.
REACH = 0.91
# How high a foot is one frame into its swing (metres): under the motion check's contact height
# a foot still swinging would count as standing there.
CLEAR = 0.03
# Frames of the Gaussian over how far the hips come down for the standing legs.
LOWER_SMOOTHING = 1.0


def _rise(rig, side):
    """How far the foot's lowest joint is above its rest height."""
    world = rig.matrix_world
    return min((world @ bone.head).z - (world @ bone.bone.head_local).z
               for bone in (feet._bone(rig, side, part) for part in ("Foot", "ToeBase", "Toe_End")))


def _stance(lows, ys, step):
    """The frames of a cycle a foot stands: its longest run, round the cycle, low on the ground
    and carried back."""
    count = len(ys)
    floor = min(lows)
    flags = [lows[index] < floor + LOW and ys[(index + 1) % count] - ys[index] >= step * BACKWARD
             for index in range(count)]
    if not any(flags) or all(flags):
        raise RuntimeError("a foot has no stance to hold")
    start = next(index for index in range(count) if flags[index] and not flags[index - 1])
    runs, run = [], []
    for offset in range(count):
        index = (start + offset) % count
        if flags[index]:
            run.append(index)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    return max(runs, key=len)


def _lower(rig, cycle, last, goals, stances):
    """Lowers the hips over the cycle as far as the standing legs need to reach their held ankles
    within REACH of their length, evenly, keying the hips on every frame."""
    world = rig.matrix_world
    hips = rig.pose.bones[planted_feet.HIPS]
    to_rest = hips.bone.matrix_local.to_3x3().inverted() @ world.to_3x3().inverted()
    drops = []
    for index in cycle:
        bpy.context.scene.frame_set(index)
        drop = 0.0
        for side in feet.SIDES:
            if index not in stances[side]:
                continue
            thigh, shin = feet._bone(rig, side, "UpLeg"), feet._bone(rig, side, "Leg")
            leg = REACH * (thigh.bone.length + shin.bone.length)
            hip, goal = world @ thigh.head, goals[side][0][index]
            across = (hip - goal).xy.length
            drop = max(drop, hip.z - goal.z - math.sqrt(max(leg * leg - across * across, 0.0)))
        drops.append(drop)
    count = len(drops)
    # Widened by a frame first, so the Gaussian doesn't take the peak back off.
    held = [Vector((max(drops[(index + offset) % count] for offset in (-1, 0, 1)), 0.0, 0.0)) for index in range(count)]
    even = clip_smooth.gauss(held, LOWER_SMOOTHING, Vector(), True)
    for frame in range(last + 1):
        bpy.context.scene.frame_set(frame)
        hips.location = hips.location + to_rest @ Vector((0.0, 0.0, -even[frame % last].x))
        hips.keyframe_insert("location", frame=frame)


def _hermite(start, end, velocity, along):
    """The cubic from `start` to `end`, leaving and arriving at `velocity` (per unit of `along`)."""
    squared, cubed = along * along, along * along * along
    return (start * (2.0 * cubed - 3.0 * squared + 1.0) + end * (3.0 * squared - 2.0 * cubed)
            + velocity * (cubed - 2.0 * squared + along) + velocity * (cubed - squared))


def _targets(path, stance, rest, step, last):
    """Per frame of the cycle, the ankle's place and how far the foot lies flat: carried back at
    the pace through the stance, centred on the clip's own stance, and between stances on a curve
    that leaves and lands at that speed, as high as the clip's own swing."""
    count = len(path)
    middle = sum((path[index] for index in stance), Vector()) / len(stance)
    centre = (len(stance) - 1) / 2.0
    pinned = {index: Vector((middle.x, middle.y + step * (at - centre), rest)) for at, index in enumerate(stance)}
    span = (stance[0] - stance[-1]) % count
    height = max(path[index].z for index in range(count) if index not in pinned) - rest
    velocity = Vector((0.0, step * span, 0.0))
    # The power of the swing's sine that clears the ground a frame in, however high the swing.
    lift = math.log(CLEAR / height) / math.log(math.sin(math.pi / span))
    places, flats = [], []
    for index in range(count):
        if index in pinned:
            places.append(pinned[index])
            flats.append(1.0)
            continue
        after = (index - stance[-1]) % count
        along = after / span
        place = _hermite(pinned[stance[-1]], pinned[stance[0]], velocity, along)
        place.z = rest + height * math.sin(math.pi * along) ** lift
        places.append(place)
        flats.append(feet._ease(1.0 - min(after, span - after) / (max(BLEND, last // FLAT_SHARE) + 1)))
    return places, flats


def pace(rig, action, speed, fps):
    """Holds the standing feet of looping `action` at `speed` (metres a second of the clip's own
    units), keying its hips and legs on every frame."""
    last = int(round(action.frame_range[1]))
    cycle = range(last)
    step = speed / fps
    keyed = [(side, part) for side in feet.SIDES for part in ("UpLeg", "Leg", "Foot", "ToeBase")]
    with planted_feet._playing(rig, action):
        world = rig.matrix_world
        paths, headings = feet._capture(rig, cycle)
        lows = {side: [] for side in feet.SIDES}
        for frame in cycle:
            bpy.context.scene.frame_set(frame)
            for side in feet.SIDES:
                lows[side].append(_rise(rig, side))
        goals, poles, stances, turned = {}, {}, {}, {}
        for side in feet.SIDES:
            rest = (world @ feet._bone(rig, side, "Foot").bone.head_local).z
            stances[side] = _stance(lows[side], [point.y for point in paths[side]], step)
            goals[side] = _targets(paths[side], stances[side], rest, step, last)
            # The stance's heading: a foot tipping onto its toes has a wild one of its own.
            turned[side] = sorted(headings[side][at] for at in stances[side])[len(stances[side]) // 2]
        _lower(rig, cycle, last, goals, stances)
        for side in feet.SIDES:
            poles[side] = feet._own_knees(rig, side, cycle, goals[side][0], True)
        for frame in range(last + 1):
            bpy.context.scene.frame_set(frame)
            index = frame % last
            for side in feet.SIDES:
                feet._bend(rig, side, goals[side][0][index], poles[side][index])
                feet._lay(rig, side, turned[side], goals[side][1][index])
            for side, part in keyed:
                feet._bone(rig, side, part).keyframe_insert("rotation_quaternion", frame=frame)
        for side in feet.SIDES:
            flags = [index % last in stances[side] for index in range(last + 1)]
            for part in ("UpLeg", "Leg", "Foot"):
                feet._even_foot(action, side, flags, range(last + 1), True, part)
