"""Motion between the keys (#1071): a clip's sparse keys filled in to every frame, and overlap and
follow-through along the rig's chains, so its parts don't all start and stop at once.

A pose is clips' {bone: (rx, ry, rz)} (plus "root_loc"); a clip here is one pose per frame.

- `fill` interpolates the keys to every frame with smooth, clamped tangents (no overshoot at a
  key, like Blender's auto-clamped handles), across the seam on a loop, so a loop never eases
  to a stop at its ends.
- `follow` makes each named bone trail its parent: the parent's turn (and the root's shift,
  seen from the bone) goes through a small second-order spring (frequency, damping, response),
  and the bone keeps the difference, so it starts late and overshoots a little. Down a chain
  (spine, neck, head, ears; hips, tail) each bone trails the one before it, which already
  trails: follow-through. A loop runs the spring until it repeats, so its last frame meets its
  first; a one-shot clip starts it at rest and fades it out over its last frames.

The spring is the second-order system from t3ssel8r's "Giving Personality to Procedural
Animations using Math": `frequency` (Hz) is how fast it responds, `damping` how much it wobbles
(below 1 it overshoots), `response` how it starts (0 eases in, above 1 overshoots at once, below
0 winds up the other way first).
"""

import math

from mathutils import Euler, Quaternion, Vector

# How many cycles a loop's spring runs before the one that's kept, so it has settled into the loop.
WARM_CYCLES = 6
# Over how many last frames a one-shot clip's lag fades out, so it ends on its last key, the pose
# the game blends on from (a spring still swinging would snap when the next clip takes over).
FADE_FRAMES = 6


def _tangents(times, values, loop):
    """A tangent per key: the slope across its neighbours, flat at a peak or a dip (and at a
    one-shot clip's ends), so the curve never swings past a key."""
    count = len(values)
    period = times[-1] - times[0]
    out = []
    for index in range(count):
        if loop:
            # The last key is the first one again: neighbours wrap around the seam.
            before = index - 1 if index > 0 else count - 2
            after = index + 1 if index < count - 1 else 1
            t_before = times[before] - (period if index == 0 else 0)
            t_after = times[after] + (period if index == count - 1 else 0)
        elif index in (0, count - 1):
            out.append(0.0)
            continue
        else:
            before, after = index - 1, index + 1
            t_before, t_after = times[before], times[after]
        rise, fall = values[after] - values[index], values[index] - values[before]
        out.append(0.0 if rise * fall <= 0.0 else (values[after] - values[before]) / (t_after - t_before))
    return out


def _hermite(t0, t1, v0, v1, m0, m1, t):
    span = t1 - t0
    s = (t - t0) / span
    return ((2 * s ** 3 - 3 * s ** 2 + 1) * v0 + (s ** 3 - 2 * s ** 2 + s) * span * m0
            + (-2 * s ** 3 + 3 * s ** 2) * v1 + (s ** 3 - s ** 2) * span * m1)


def _channel(times, values, frames, loop):
    if len(times) == 1:
        return [values[0]] * len(frames)
    slopes = _tangents(times, values, loop)
    out, key = [], 0
    for frame in frames:
        while key < len(times) - 2 and frame > times[key + 1]:
            key += 1
        out.append(_hermite(times[key], times[key + 1], values[key], values[key + 1], slopes[key],
                            slopes[key + 1], frame))
    return out


def fill(poses, loop):
    """Every frame from the first key to the last, each channel interpolated through its keys. A
    bone or axis a key leaves out is at rest there. Returns [(frame, pose)]."""
    times = [frame for frame, _pose in poses]
    frames = list(range(times[0], times[-1] + 1))
    names = sorted({name for _frame, pose in poses for name in pose})
    filled = [{} for _frame in frames]
    for name in names:
        axes = [_channel(times, [pose.get(name, (0.0, 0.0, 0.0))[axis] for _frame, pose in poses], frames, loop)
                for axis in range(3)]
        for index, pose in enumerate(filled):
            pose[name] = tuple(axes[axis][index] for axis in range(3))
    return list(zip(frames, filled))


def spring(targets, frequency, damping, response, fps, loop):
    """`targets` (Vectors, one a frame) through the second-order system, semi-implicit Euler with
    the stable step size bound. A loop (whose last target is its first) runs WARM_CYCLES cycles
    first and keeps the next, closed onto its start."""
    k1 = damping / (math.pi * frequency)
    k2 = 1.0 / (2.0 * math.pi * frequency) ** 2
    k3 = response * damping / (2.0 * math.pi * frequency)
    step = 1.0 / fps
    k2 = max(k2, step * step / 2 + step * k1 / 2, step * k1)
    cycle = targets[:-1] if loop else targets
    rounds = WARM_CYCLES + 1 if loop else 1
    y, speed, previous = cycle[0].copy(), cycle[0] * 0.0, cycle[0]
    out = []
    for _round in range(rounds):
        out = []
        for target in cycle:
            change = (target - previous) / step
            previous = target
            y = y + speed * step
            speed = speed + step * (target + k3 * change - y - k1 * speed) / k2
            out.append(y.copy())
    if loop:
        out.append(out[0].copy())
    return out


class Rig:
    """What `follow` needs to know of an armature: each bone's parent, its rest orientation in the
    armature and its length and direction there, read once from the rig's bones."""

    def __init__(self, armature):
        self.parent = {bone.name: bone.parent.name if bone.parent else None for bone in armature.data.bones}
        self.rest = {bone.name: bone.matrix_local.to_quaternion() for bone in armature.data.bones}
        self.vector = {bone.name: bone.tail_local - bone.head_local for bone in armature.data.bones}
        self.root = next(name for name, parent in self.parent.items() if parent is None)

    def chain(self, name):
        """The bone's ancestors, root first."""
        out = []
        while self.parent[name] is not None:
            name = self.parent[name]
            out.append(name)
        return list(reversed(out))


def _turn(pose, name):
    return Euler(pose.get(name, (0.0, 0.0, 0.0)), "XYZ").to_quaternion()


def _posed(rig, pose, name):
    """How far a bone is turned from its rest, in the armature's axes: its parent's turn, then
    its own turn about its own rest axes."""
    turned = Quaternion()
    for bone in rig.chain(name) + [name]:
        turned = turned @ rig.rest[bone] @ _turn(pose, bone) @ rig.rest[bone].inverted()
    return turned


def _fade(left):
    """1 until FADE_FRAMES before the end, easing to 0 on the last frame (`left` frames to go)."""
    share = min(1.0, left / FADE_FRAMES)
    return share * share * (3.0 - 2.0 * share)


def _vector(turn):
    axis, angle = turn.to_axis_angle()
    return axis * angle if angle <= math.pi else axis * (angle - 2 * math.pi)


def follow(rig, clip, chains, scale, fps, loop):
    """Makes each bone in `chains` ({bone: (frequency, damping, response, shift)}) trail its parent
    through `clip` ([(frame, pose)], every frame), parents before their children. `shift` is how
    much the root's movement swings the bone too, as a weight on the turn that would carry the
    bone's tip along with it. `scale` is the model's, which root_loc is scaled by."""
    root_rest = rig.rest[rig.root]
    for name in sorted(chains, key=lambda bone: len(rig.chain(bone))):
        frequency, damping, response, shift = chains[name]
        reach = rig.vector[name]
        drives = []
        for _frame, pose in clip:
            parent = _posed(rig, pose, rig.parent[name])
            moved = root_rest @ (Vector(pose.get("root_loc", (0.0, 0.0, 0.0))) * scale)
            carried = reach.cross(moved) / reach.length_squared
            drives.append(_vector(parent) + carried * shift)
        trailed = spring(drives, frequency, damping, response, fps, loop)
        for index, ((_frame, pose), drive, lag) in enumerate(zip(clip, drives, trailed)):
            parent = _posed(rig, pose, rig.parent[name])
            behind = (lag - drive) * (1.0 if loop else _fade(len(clip) - 1 - index))
            if behind.length == 0.0:
                continue
            # The lag is a turn in the armature's axes; seen from the bone's own rest axes under
            # its posed parent, it turns the bone before its own pose does.
            local = (parent @ rig.rest[name]).inverted() @ Quaternion(behind.normalized(), behind.length)
            local = local @ parent @ rig.rest[name]
            own = Euler(pose.get(name, (0.0, 0.0, 0.0)), "XYZ")
            pose[name] = tuple((local @ own.to_quaternion()).to_euler("XYZ", own))
    return clip
