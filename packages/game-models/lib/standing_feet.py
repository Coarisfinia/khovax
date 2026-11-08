"""Standing feet held still (#2154). The motion capture behind the player's one-shots lets a foot on
the ground creep and carries the whole body across the floor, and planting per frame
(lib/planted_feet.py) snaps a foot flat or back when its ankle crosses a line. `hold` works on the
clip as a whole instead, from paths that are smooth by construction:

1. It decides when each foot stands: slow enough, and on a clip that stands throughout, always one.
2. It carries the body back by what the standing feet drift, through the hips.
3. It pins each stance's ankle and heading, and carries a foot between two stances on an arc that
   clears the ground before the foot moves across it.
4. A two-bone IK on the thigh and shin puts the ankle there, the knee pointing the way the body
   faces (or, on a clip that leaves the ground, the way the clip's own knee does); a leg never
   quite straightens, as a straight knee is where IK snaps."""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector

from lib import clip_smooth, planted_feet

SIDES = planted_feet.SIDES
# A foot on a clip that leaves the ground stands while it's this close to it (metres).
LOW = 0.05
# A foot on a clip that stands throughout stands while it moves no faster (metres a frame).
STILL = 0.012
# The shortest stance and the shortest step, in frames: a step shorter than this stays planted.
SHORTEST_STANCE = 5
SHORTEST_STEP = 6
# How high a step lifts the foot, and the part of a step at either end spent lifting, not moving.
STEP_HEIGHT = 0.08
LIFTING = 0.1
# On a long flight, the part of it at either end that a foot keeps its heading for, so it has
# stopped turning before it lands.
TURNING = 0.2
# Frames a foot on a long flight takes to settle onto where it lands.
LANDING = 6
# How long, in frames, a clip that leaves the ground takes to go from flat feet to its own.
FLAT_EASE = 10
# The leg's reach, as a share of its length: past SOFT it is squeezed smoothly, up to LIMIT.
SOFT = 0.94
LIMIT = 0.995
BODY_SMOOTHING = 3.0
# Frames of the Gaussian over the plane a knee bends in.
POLE_SMOOTHING = 4.0
# The way the model faces at rest (in the rig's world).
FORWARD = Vector((0.0, -1.0, 0.0))
# Frames of the Gaussian over a foot's turn while it steps, and how many frames from a stance it
# takes to come in. A foot held flat under a swinging shin whips; evening it out moves no ankle.
FOOT_SMOOTHING = 1.5
FOOT_EDGE = 3


def _ease(amount):
    amount = min(max(amount, 0.0), 1.0)
    return amount * amount * amount * (amount * (6.0 * amount - 15.0) + 10.0)


def _gauss(values, sigma):
    return clip_smooth.gauss(values, sigma, values[0] * 0.0)


def _runs(flags):
    """The (first, last) of each run of True in `flags`."""
    out, start = [], None
    for index, flag in enumerate(flags + [False]):
        if flag and start is None:
            start = index
        elif not flag and start is not None:
            out.append((start, index - 1))
            start = None
    return out


def _bone(rig, side, part):
    return rig.pose.bones["mixamorig:%s%s" % (side, part)]


def _capture(rig, frames):
    """Per side, per frame: the ankle's place and the foot's heading (radians, unwrapped)."""
    world = rig.matrix_world
    places = {side: [] for side in SIDES}
    headings = {side: [] for side in SIDES}
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        for side in SIDES:
            foot, toe = _bone(rig, side, "Foot"), _bone(rig, side, "ToeBase")
            places[side].append(world @ foot.head)
            now = world.to_3x3() @ (toe.head - foot.head)
            was = world.to_3x3() @ (toe.bone.head_local - foot.bone.head_local)
            yaw = math.atan2(now.y, now.x) - math.atan2(was.y, was.x)
            if headings[side]:
                yaw += 2.0 * math.pi * round((headings[side][-1] - yaw) / (2.0 * math.pi))
            headings[side].append(yaw)
    return places, headings


def _speeds(path):
    return [0.0] + [(after - before).xy.length for before, after in zip(path, path[1:])]


def _close_short_steps(flags):
    """`flags` with every gap shorter than a step filled, the clip's ends included: a foot that
    moves only in a clip's first or last frames stays where it is."""
    runs = _runs(flags)
    if not runs:
        return flags
    out = [True] * len(flags)
    for (_, end), (start, _) in zip(runs, runs[1:]):
        if start - end - 1 >= SHORTEST_STEP:
            out[end + 1:start] = [False] * (start - end - 1)
    return out


def standing_grounded(paths):
    """Per side, whether the foot stands on each frame of a clip that stands throughout: slow
    enough, and on a frame where neither is, the slower one, so one always does."""
    speeds = {side: _speeds(paths[side]) for side in SIDES}
    flags = {side: [speed < STILL for speed in speeds[side]] for side in SIDES}
    count = len(paths[SIDES[0]])
    for index in range(count):
        if not any(flags[side][index] for side in SIDES):
            flags[min(SIDES, key=lambda side: speeds[side][index])][index] = True
    flags = {side: _close_short_steps(flags[side]) for side in SIDES}
    # A stance too short to read goes, where the other foot carries the body through it.
    for side, other in (SIDES, SIDES[::-1]):
        for start, end in _runs(flags[side]):
            if end - start + 1 >= SHORTEST_STANCE or not all(flags[other][start:end + 1]):
                continue
            flags[side][start:end + 1] = [False] * (end - start + 1)
            # At a clip's end it keeps that one frame, where the foot starts or ends its step.
            if start == 0:
                flags[side][0] = True
            elif end == len(flags[side]) - 1:
                flags[side][end] = True
    return flags


def standing_free(paths, rests):
    """Per side, whether the foot stands on each frame of a clip that leaves the ground."""
    flags = {}
    for side in SIDES:
        low = [abs(point.z - rests[side]) < LOW for point in paths[side]]
        flags[side] = low
        for start, end in _runs(low):
            if end - start + 1 < SHORTEST_STANCE:
                flags[side][start:end + 1] = [False] * (end - start + 1)
    return flags


def _body_shift(paths, flags, rests, grounded):
    """Per frame, the world shift that holds the standing feet where they are: their drift
    undone, and on a clip that stands throughout, the body lowered onto them."""
    count = len(paths[SIDES[0]])
    shift = []
    total = Vector((0.0, 0.0, 0.0))
    for index in range(count):
        if grounded:
            # Between the feet, not with either: a clip that travels stays where it started.
            midway = sum((paths[side][index].xy for side in SIDES), Vector((0.0, 0.0))) / len(SIDES)
            start = sum((paths[side][0].xy for side in SIDES), Vector((0.0, 0.0))) / len(SIDES)
            total = (start - midway).to_3d()
        elif index:
            moves = [(paths[side][index] - paths[side][index - 1]).xy for side in SIDES
                     if flags[side][index] and flags[side][index - 1]]
            if moves:
                total -= (sum(moves, Vector((0.0, 0.0))) / len(moves)).to_3d()
        lifts = [paths[side][index].z - rests[side] for side in SIDES if flags[side][index]]
        shift.append(Vector((total.x, total.y, -min(lifts) if grounded and lifts else 0.0)))
    return _gauss(shift, BODY_SMOOTHING)


def _within_reach(pin, hips, leg):
    """`pin` drawn in across the floor towards the hips until the leg reaches it from `hips`, the
    hip's place on each frame of the stance, without passing SOFT of its length `leg`."""
    middle = sum((hip.xy for hip in hips), Vector((0.0, 0.0))) / len(hips)
    def fits(share):
        spot = (middle + (pin.xy - middle) * share).to_3d()
        spot.z = pin.z
        return max((hip - spot).length for hip in hips) <= SOFT * leg
    if fits(1.0):
        return pin
    low, high = 0.0, 1.0
    for _ in range(24):
        low, high = ((low + high) / 2.0, high) if fits((low + high) / 2.0) else (low, (low + high) / 2.0)
    spot = (middle + (pin.xy - middle) * low).to_3d()
    spot.z = pin.z
    return spot


def _targets(path, heading, runs, rest, grounded, hips, leg):
    """One foot's ankle place and heading on every frame: pinned through each stance, on an arc
    between two, and on a free clip its own path from the last stance's offset beyond."""
    pins, turned = [], []
    for start, end in runs:
        span = path[start:end + 1]
        mean = sum(span, Vector((0.0, 0.0, 0.0))) / len(span)
        pin = Vector((mean.x, mean.y, rest))
        pins.append(_within_reach(pin, hips[start:end + 1], leg) if grounded else pin)
        turned.append(sum(heading[start:end + 1]) / len(span))
    places, headings = [], []
    for index in range(len(path)):
        at = sum(1 for start, _ in runs if start <= index) - 1
        if at >= 0 and index <= runs[at][1]:
            places.append(pins[at].copy())
            headings.append(turned[at])
        elif at >= 0 and at + 1 < len(runs):
            span = runs[at + 1][0] - runs[at][1]
            along = (index - runs[at][1]) / span
            moved = _ease((along - LIFTING) / (1.0 - 2.0 * LIFTING))
            place = pins[at].lerp(pins[at + 1], moved)
            if grounded:
                place.z = rest + STEP_HEIGHT * math.sin(math.pi * along) ** 2
            else:
                # A long flight: the clip's own path, shifted from pin to pin.
                left = pins[at] - path[runs[at][1]]
                right = pins[at + 1] - path[runs[at + 1][0]]
                place = path[index] + left.lerp(right, _ease(along))
                # It arrives at rest: over the last frames it settles onto the pin.
                place = place.lerp(pins[at + 1], _ease(1.0 - (runs[at + 1][0] - index) / LANDING))
            places.append(place)
            headings.append(turned[at] + (turned[at + 1] - turned[at]) * (moved if grounded else _ease((along - TURNING) / (1.0 - 2.0 * TURNING))))
        elif at >= 0:
            places.append(path[index] + pins[at] - path[runs[at][1]])
            headings.append(heading[index] + turned[at] - heading[runs[at][1]])
        elif runs:
            places.append(path[index] + pins[0] - path[runs[0][0]])
            headings.append(heading[index] + turned[0] - heading[runs[0][0]])
        else:
            places.append(path[index].copy())
            headings.append(heading[index])
    return places, headings


def _flatness(flags, grounded):
    """How flat the foot lies on each frame: always on a clip that stands throughout, else easing
    from each stance to the clip's own foot over FLAT_EASE frames."""
    if grounded:
        return [1.0] * len(flags)
    out = [0.0] * len(flags)
    for start, end in _runs(flags):
        for index in range(len(flags)):
            away = max(start - index, index - end, 0)
            out[index] = max(out[index], _ease(1.0 - away / FLAT_EASE))
    return out


def _aim(rig, bone, from_point, to_point):
    """Turns `bone` so the world direction `from_point` holds now points at `to_point`."""
    world = rig.matrix_world
    origin = world @ bone.head
    swing = (from_point - origin).rotation_difference(to_point - origin)
    turn = world.to_3x3().inverted() @ swing.to_matrix() @ world.to_3x3()
    bone.matrix = Matrix.Translation(bone.head) @ (turn @ bone.matrix.to_3x3()).to_4x4()
    bpy.context.view_layer.update()


def _poles(rig, frames):
    """Per frame, the way the body faces, smoothed, for its knees to point: a clip's own knee
    wobbles around the leg near straight and swaps sides when a step sweeps the foot past it."""
    hips = rig.pose.bones[planted_feet.HIPS]
    to_rest = hips.bone.matrix_local.to_3x3().inverted()
    facing = []
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        facing.append(rig.matrix_world.to_3x3() @ hips.matrix.to_3x3() @ to_rest @ FORWARD)
    return _gauss(facing, POLE_SMOOTHING)


def _own_knees(rig, side, frames, goals, loop=False):
    """Per frame, the way the clip's own knee points off the line from hip to goal, smoothed: on a
    clip that leaves the ground the body turns right over, and the knee follows the clip."""
    world = rig.matrix_world
    raw = []
    for index, frame in enumerate(frames):
        bpy.context.scene.frame_set(frame)
        hip, knee = world @ _bone(rig, side, "UpLeg").head, world @ _bone(rig, side, "Leg").head
        aim = (goals[index] - hip).normalized()
        pole = (knee - hip) - aim * (knee - hip).dot(aim)
        raw.append(pole.normalized() if pole.length > 1e-3 else FORWARD.copy())
    return clip_smooth.gauss(raw, POLE_SMOOTHING, raw[0] * 0.0, loop)


def _bend(rig, side, target, pole):
    """Bends one leg to put its ankle at world `target`, its knee towards `pole`."""
    world = rig.matrix_world
    thigh, shin, foot = _bone(rig, side, "UpLeg"), _bone(rig, side, "Leg"), _bone(rig, side, "Foot")
    hip, knee = world @ thigh.head, world @ shin.head
    upper, lower = (knee - hip).length, ((world @ foot.head) - knee).length
    wanted = target - hip
    reach = wanted.length / (upper + lower)
    if reach > SOFT:
        room = LIMIT - SOFT
        reach = SOFT + room * (1.0 - math.exp(-(reach - SOFT) / room))
    distance = reach * (upper + lower)
    aim = wanted.normalized()
    pole = (pole - aim * pole.dot(aim)).normalized()
    along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
    new_knee = hip + aim * along + pole * math.sqrt(max(upper * upper - along * along, 0.0))
    _aim(rig, thigh, knee, new_knee)
    _aim(rig, shin, world @ foot.head, hip + aim * distance)


def _lay(rig, side, heading, amount):
    """Turns the foot `amount` of the way to flat on the floor, at `heading` about the vertical."""
    world = rig.matrix_world.to_3x3()
    foot, toe = _bone(rig, side, "Foot"), _bone(rig, side, "ToeBase")
    flat = (world.inverted() @ Matrix.Rotation(heading, 3, "Z") @ world @ foot.bone.matrix_local.to_3x3()).to_quaternion()
    turned = foot.matrix.to_quaternion().slerp(flat, amount)
    foot.matrix = Matrix.Translation(foot.head) @ turned.to_matrix().to_4x4()
    toe.rotation_quaternion = toe.rotation_quaternion.slerp(Quaternion(), amount)
    bpy.context.view_layer.update()


def _even_foot(action, side, flags, frames, loop=False, part="Foot"):
    """Evens out one foot's turn while it steps, leaving its stances as they are."""
    found = clip_smooth.action_curves(action)
    path = 'pose.bones["mixamorig:%s%s"].rotation_quaternion' % (side, part)
    curves = [found[(path, channel)] for channel in range(4)]
    turns = [Vector([curve.evaluate(frame) for curve in curves]) for frame in frames]
    for index in range(1, len(turns)):
        if turns[index].dot(turns[index - 1]) < 0.0:
            turns[index] = -turns[index]
    evened = (clip_smooth.gauss(turns[:-1], FOOT_SMOOTHING, turns[0] * 0.0, True) + [turns[0] * 0.0]
              if loop else _gauss(turns, FOOT_SMOOTHING))
    if loop:
        evened[-1] = evened[0]
    for index, (turn, even) in enumerate(zip(turns, evened)):
        near = min((abs(index - other) for other, stands in enumerate(flags) if stands), default=FOOT_EDGE)
        mixed = turn.lerp(even, _ease(near / FOOT_EDGE)).normalized()
        for channel, curve in enumerate(curves):
            curve.keyframe_points[index].co.y = mixed[channel]
    for curve in curves:
        curve.update()


def hold(rig, action, grounded):
    """Holds `action`'s standing feet still and flat, keying its hips and legs on every frame.
    `grounded`: the clip stands throughout, so a foot is on the floor on every frame."""
    first, last = (int(round(frame)) for frame in action.frame_range)
    frames = range(first, last + 1)
    keyed = [(side, part) for side in SIDES for part in ("UpLeg", "Leg", "Foot", "ToeBase")]
    with planted_feet._playing(rig, action):
        world = rig.matrix_world
        rests = {side: (world @ _bone(rig, side, "Foot").bone.head_local).z for side in SIDES}
        paths, _ = _capture(rig, frames)
        if grounded:
            flags = standing_grounded(paths)
        else:
            flags = standing_free(paths, rests)
        shift = _body_shift(paths, flags, rests, grounded)
        hips = rig.pose.bones[planted_feet.HIPS]
        to_rest = hips.bone.matrix_local.to_3x3().inverted() @ world.to_3x3().inverted()
        for index, frame in enumerate(frames):
            bpy.context.scene.frame_set(frame)
            hips.location = hips.location + to_rest @ shift[index]
            hips.keyframe_insert("location", frame=frame)
        paths, headings = _capture(rig, frames)
        hip_paths, legs = {side: [] for side in SIDES}, {}
        for side in SIDES:
            thigh, shin = _bone(rig, side, "UpLeg"), _bone(rig, side, "Leg")
            legs[side] = thigh.bone.length + shin.bone.length
            for frame in frames:
                bpy.context.scene.frame_set(frame)
                hip_paths[side].append(world @ thigh.head)
        goals = {side: _targets(paths[side], headings[side], _runs(flags[side]), rests[side], grounded,
                                hip_paths[side], legs[side]) for side in SIDES}
        flats = {side: _flatness(flags[side], grounded) for side in SIDES}
        facing = _poles(rig, frames) if grounded else None
        poles = {side: facing or _own_knees(rig, side, frames, goals[side][0]) for side in SIDES}
        for index, frame in enumerate(frames):
            bpy.context.scene.frame_set(frame)
            for side in SIDES:
                _bend(rig, side, goals[side][0][index], poles[side][index])
                _lay(rig, side, goals[side][1][index], flats[side][index])
            for side, part in keyed:
                _bone(rig, side, part).keyframe_insert("rotation_quaternion", frame=frame)
        for side in SIDES:
            _even_foot(action, side, flags[side], frames)
