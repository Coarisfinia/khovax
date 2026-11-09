"""The player's Run rebuilt as one smooth cycle (#2181). Corrections around each stance of the
capture leave a kink where the foot leaves the ground, so `retime` shortens the capture to the
game's cadence for the body and arms, and `build` replaces the legs: each leg's thigh and knee
angles follow one curve through the whole cycle, through the angles that carry the ankle back at
the pace while it stands. Nothing of the capture's legs is left to correct."""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector

from lib import clip_smooth, planted_feet, standing_feet as feet

# Frames a stride takes: the stride covers the game's pace in a reach a leg can make.
CYCLE = 14
# Half the time a foot stands, in frames from its middle (three frames): a short stance keeps the
# knee from straightening fast, and the body high.
STANCE = 1.0
# The swing, in frames after the foot leaves the ground: (when, thigh, knee). The thigh's angle is
# from straight down, forward positive, the knee's its bend; degrees. Heel kicked up behind, knee
# driven through, leg reaching out to land.
SWING = ((3.5, -20.0, 90.0), (7.0, 55.0, 140.0), (10.0, 80.0, 60.0))
# How far the foot tips toe-down at the swing's middle (radians), flat where it leaves and lands.
TIP = 0.7
# How far the hips bob (metres), highest in the stances, so a standing leg keeps its length and its
# knee barely moves, and the share of a leg's length it reaches at most: near straight, a knee
# bends fast.
BOB = 0.03
REACH = 0.91


def retime(action, frames):
    """Resamples every channel of looping `action` to `frames` frames, keeping its shape and
    closing the seam; quaternions stay next to the key before, so they interpolate."""
    found = clip_smooth.action_curves(action)
    last = int(round(action.frame_range[1]))
    groups = {}
    for (path, index), curve in found.items():
        groups.setdefault(path, {})[index] = curve
    for path, channels in groups.items():
        curves = [channels[index] for index in sorted(channels)]
        keys = [Vector([curve.evaluate(frame) for curve in curves]) for frame in range(last + 1)]
        if path.endswith("rotation_quaternion"):
            for index in range(1, len(keys)):
                if keys[index].dot(keys[index - 1]) < 0.0:
                    keys[index] = -keys[index]
        for frame in range(frames + 1):
            at = frame * last / frames
            low = min(int(at), last - 1)
            value = keys[low].lerp(keys[low + 1], at - low)
            for curve, channel in zip(curves, value):
                if frame == 0:
                    curve.keyframe_points.clear()
                    curve.keyframe_points.add(frames + 1)
                point = curve.keyframe_points[frame]
                point.co = (frame, channel)
                point.interpolation = "LINEAR"
        for curve in curves:
            curve.update()
    bpy.context.view_layer.update()


def _offset(time, centre):
    """`time` from the stance centred on `centre`, wrapped into the cycle's half either side."""
    return ((time - centre + CYCLE / 2.0) % CYCLE) - CYCLE / 2.0


def _standing(time, centre, across, rest, step):
    """Where the ankle stands at `time`: straight back at the pace, under the stance's middle."""
    return Vector((across, step * _offset(time, centre), rest))


def _angles(hip, ankle, upper, lower):
    """The thigh's and the knee's angles (degrees, see SWING) that put an ankle at `ankle` from
    `hip`, seen from the side."""
    reach = Vector((ankle.y - hip.y, ankle.z - hip.z))
    distance = min(reach.length, upper + lower - 1e-4)
    knee = math.pi - math.acos(min(max((upper ** 2 + lower ** 2 - distance ** 2) / (2.0 * upper * lower), -1.0), 1.0))
    towards = math.atan2(-reach.x, -reach.y)
    thigh = towards + math.atan2(lower * math.sin(knee), upper + lower * math.cos(knee))
    return math.degrees(thigh), math.degrees(knee)


def _spline(knots):
    """The periodic cubic through `knots` ((time, value), sorted, one cycle): a function of time
    whose value, speed and acceleration all run on round the cycle."""
    count = len(knots)
    times = [knot[0] for knot in knots]
    values = [knot[1] for knot in knots]
    gaps = [((times[(index + 1) % count] - times[index]) % CYCLE) for index in range(count)]
    rows = [[0.0] * (count + 1) for _ in range(count)]
    for index in range(count):
        before, after = gaps[index - 1], gaps[index]
        rows[index][(index - 1) % count] += before
        rows[index][index] += 2.0 * (before + after)
        rows[index][(index + 1) % count] += after
        rows[index][count] = 6.0 * ((values[(index + 1) % count] - values[index]) / after
                                    - (values[index] - values[index - 1]) / before)
    for column in range(count):
        pivot = max(range(column, count), key=lambda row: abs(rows[row][column]))
        rows[column], rows[pivot] = rows[pivot], rows[column]
        for row in range(count):
            if row != column:
                ratio = rows[row][column] / rows[column][column]
                rows[row] = [left - ratio * right for left, right in zip(rows[row], rows[column])]
    bends = [rows[index][count] / rows[index][index] for index in range(count)]

    def value(time):
        index = max((at for at in range(count) if (time - times[at]) % CYCLE <= gaps[at]),
                    key=lambda at: times[at] if times[at] <= time else times[at] - CYCLE)
        gap, along = gaps[index], (time - times[index]) % CYCLE
        left, right = bends[index], bends[(index + 1) % count]
        slope = (values[(index + 1) % count] - values[index]) / gap - gap * (2.0 * left + right) / 6.0
        return values[index] + along * (slope + along * (left / 2.0 + along * (right - left) / (6.0 * gap)))
    return value


def _down(angle):
    """The world direction, seen from the side, of a bone `angle` degrees forward of straight down
    (the model faces -Y)."""
    return Vector((-math.sin(math.radians(angle)), -math.cos(math.radians(angle))))


def _stance_centre(rig, cycle):
    """The middle of the left foot's stance in the retimed capture, on a whole frame."""
    heights = []
    for frame in cycle:
        bpy.context.scene.frame_set(frame)
        heights.append((rig.matrix_world @ feet._bone(rig, "Left", "Foot").head).z)
    low = min(heights)
    turn = sum((Vector((math.cos(2.0 * math.pi * frame / CYCLE), math.sin(2.0 * math.pi * frame / CYCLE)))
                for frame, height in zip(cycle, heights) if height < low + 0.05), Vector((0.0, 0.0)))
    return float(round(math.atan2(turn.y, turn.x) * CYCLE / (2.0 * math.pi)) % CYCLE)


def _body(rig, cycle, centres, acrosses, rest, step):
    """Per frame, how far the hips move up or down: an even bob, highest in the stances, at the
    height where a standing leg reaches both ends of its stance within REACH of its length."""
    world = rig.matrix_world
    hips = rig.pose.bones[planted_feet.HIPS]
    bob = [BOB * math.cos(4.0 * math.pi * (frame - centres["Left"]) / CYCLE) for frame in cycle]
    now = []
    height = math.inf
    for frame in cycle:
        bpy.context.scene.frame_set(frame)
        now.append((world @ hips.head).z)
        for side in feet.SIDES:
            offset = _offset(frame, centres[side])
            if abs(offset) > STANCE:
                continue
            thigh = feet._bone(rig, side, "UpLeg")
            leg = REACH * (thigh.bone.length + feet._bone(rig, side, "Leg").bone.length)
            hip = world @ thigh.head
            goal = Vector((acrosses[side], step * offset, rest[side]))
            across = (hip - goal).xy.length
            if across >= leg:
                raise RuntimeError("Run: %s ankle held out of reach on frame %d" % (side, frame))
            height = min(height, goal.z + math.sqrt(leg * leg - across * across) + now[-1] - hip.z - bob[frame])
    return [height + bob[frame] - now[frame] for frame in cycle]


def build(rig, action, speed, fps):
    """Replaces the legs and the hips' height of looping `action` at `speed` (metres a second of
    the clip's own units), keying them on every frame."""
    step = speed / fps
    cycle = range(CYCLE)
    keyed = [(side, part) for side in feet.SIDES for part in ("UpLeg", "Leg", "Foot", "ToeBase")]
    with planted_feet._playing(rig, action):
        world = rig.matrix_world
        hips = rig.pose.bones[planted_feet.HIPS]
        to_rest = hips.bone.matrix_local.to_3x3().inverted() @ world.to_3x3().inverted()
        left = _stance_centre(rig, cycle)
        centres = {"Left": left, "Right": (left + CYCLE / 2.0) % CYCLE}
        rest = {side: (world @ feet._bone(rig, side, "Foot").bone.head_local).z for side in feet.SIDES}
        paths, _ = feet._capture(rig, cycle)
        acrosses = {side: sum(point.x for point in paths[side]) / CYCLE for side in feet.SIDES}
        moves = _body(rig, cycle, centres, acrosses, rest, step)
        for frame in range(CYCLE + 1):
            bpy.context.scene.frame_set(frame)
            hips.location = hips.location + to_rest @ Vector((0.0, 0.0, moves[frame % CYCLE]))
            hips.keyframe_insert("location", frame=frame)
        turn = world.to_3x3().inverted()
        curves = {}
        for side in feet.SIDES:
            thigh, shin = feet._bone(rig, side, "UpLeg"), feet._bone(rig, side, "Leg")
            upper, lower = thigh.bone.length, shin.bone.length
            knots = []
            for offset in (-STANCE, 0.0, STANCE):
                time = (centres[side] + offset) % CYCLE
                bpy.context.scene.frame_set(int(time))
                knots.append((time, _angles(world @ thigh.head, _standing(time, centres[side], acrosses[side], rest[side], step),
                                            upper, lower)))
            for after, turned, bent in SWING:
                knots.append(((centres[side] + STANCE + after) % CYCLE, (turned, bent)))
            knots.sort(key=lambda knot: knot[0])
            curves[side] = (_spline([(time, angles[0]) for time, angles in knots]),
                            _spline([(time, angles[1]) for time, angles in knots]))
        for frame in range(CYCLE + 1):
            bpy.context.scene.frame_set(frame)
            for side in feet.SIDES:
                thigh, shin = feet._bone(rig, side, "UpLeg"), feet._bone(rig, side, "Leg")
                hip = world @ thigh.head
                time = frame % CYCLE
                bent = curves[side][1](time)
                above = _down(curves[side][0](time))
                below = _down(curves[side][0](time) - bent)
                knee = Vector((hip.x, hip.y + thigh.bone.length * above.x, hip.z + thigh.bone.length * above.y))
                offset = _offset(time, centres[side])
                if abs(offset) <= STANCE:
                    place = _standing(time, centres[side], acrosses[side], rest[side], step)
                    tip = 0.0
                else:
                    place = Vector((acrosses[side], knee.y + shin.bone.length * below.x, knee.z + shin.bone.length * below.y))
                    along = ((offset - STANCE) % CYCLE) / (CYCLE - 2.0 * STANCE)
                    tip = TIP * math.sin(math.pi * along) ** 4
                feet._bend(rig, side, place, knee - hip)
                foot = feet._bone(rig, side, "Foot")
                flat = turn @ Matrix.Rotation(tip, 3, "X") @ world.to_3x3() @ foot.bone.matrix_local.to_3x3()
                foot.matrix = Matrix.Translation(foot.head) @ flat.to_quaternion().to_matrix().to_4x4()
                feet._bone(rig, side, "ToeBase").rotation_quaternion = Quaternion()
                bpy.context.view_layer.update()
            for side, part in keyed:
                feet._bone(rig, side, part).keyframe_insert("rotation_quaternion", frame=frame)
