"""Motion between the keys (#1071): a clip's sparse keys filled in to every frame, and overlap and
follow-through along the rig's chains, so its parts don't all start and stop at once.

A pose is clips' {bone: (rx, ry, rz)} (plus "root_loc"); a clip here is one pose per frame.

- `fill` interpolates the keys to every frame with smooth, clamped tangents (no overshoot at a
  key, like Blender's auto-clamped handles), across the seam on a loop, so a loop never eases
  to a stop at its ends. A key may name how the move into it runs (an ease, #1074): a snappy
  ease-out for a lunge, one that overshoots and comes back, or a wobble that dies down, like
  Blender's per-key interpolation and easing.
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


def _expo(s):
    return (1.0 - (1.0 + 8.0 * s) * math.exp(-8.0 * s)) / (1.0 - 9.0 * math.exp(-8.0))


def _elastic(s):
    return 1.0 - (1.0 + 7.0 * s) * math.exp(-7.0 * s) * math.cos(2.5 * math.pi * s)


def _rested(curve, speed):
    """`curve` with its `speed` at its end taken out (s^3 - s^2 is 0 at both ends, and leaves
    with no speed and ends with one), so it comes to rest on its key."""
    return lambda s: curve(s) - speed * (s ** 3 - s ** 2)


# How a move into a key runs (#1074), from 0 at the key before to 1 at this one. Each leaves its
# key with no speed but gathers it within the first frames, so a snap from a held pose doesn't
# pop (a jolt from standstill reads as one at the clip rate, and the motion check's jitter fails
# it), and each comes to rest on its key, so the move after it starts from rest: "quart" leaves
# fast and slows into the key (an ease-out: a lunge, a recoil), "expo" likewise but snappier,
# "back" swings about a tenth past the key and comes back (an overshoot), and "elastic" wobbles
# about it as it dies down, like a spring let go (an ear's flick; sparingly).
EASES = {
    "quart": lambda s: 1.0 - (1.0 - s) ** 4 * (1.0 + 4.0 * s),
    "expo": _rested(_expo, 64.0 * math.exp(-8.0) / (1.0 - 9.0 * math.exp(-8.0))),
    "back": lambda s: 1.0 - (1.0 - s) ** 2 * (1.0 + 2.0 * s - 7.0 * s * s),
    "elastic": _rested(_elastic, 8.0 * math.exp(-7.0) * 2.5 * math.pi),
}


def ease_of(key, name):
    """The ease of the move into `key` ((frame, pose) or (frame, pose, ease)) for channel `name`:
    None for the smooth default. A key's ease is a name of EASES, or {channel: name} with "*" for
    every channel it doesn't name."""
    ease = key[2] if len(key) > 2 else None
    if isinstance(ease, dict):
        ease = ease.get(name, ease.get("*"))
    if ease is not None and ease not in EASES:
        raise ValueError("no ease %r (motion.EASES)" % ease)
    return ease


def _tangents(times, values, loop, eased=None):
    """A tangent per key: the slope across its neighbours, flat at a peak or a dip (and at a
    one-shot clip's ends), so the curve never swings past a key. Flat too at either end of an
    eased move (`eased`, per move from each key to the next): an ease leaves its key at speed
    and comes to rest on the next, so a smooth move next to it meets it at rest."""
    count = len(values)
    period = times[-1] - times[0]
    eased = eased or [False] * (count - 1)
    out = []
    for index in range(count):
        before_eased = eased[index - 1] if index > 0 else (loop and eased[-1])
        after_eased = eased[index] if index < count - 1 else (loop and eased[0])
        if before_eased or after_eased:
            out.append(0.0)
            continue
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
        if rise * fall <= 0.0:
            out.append(0.0)
            continue
        # No steeper than three times the gentler side's slope: the curve then stays between its
        # keys however unevenly they are spaced (monotone cubic, Fritsch and Carlson).
        slope = (values[after] - values[before]) / (t_after - t_before)
        limit = 3.0 * min(abs(rise / (t_after - times[index])), abs(fall / (times[index] - t_before)))
        out.append(max(-limit, min(limit, slope)))
    return out


def _hermite(t0, t1, v0, v1, m0, m1, t):
    span = t1 - t0
    s = (t - t0) / span
    return ((2 * s ** 3 - 3 * s ** 2 + 1) * v0 + (s ** 3 - 2 * s ** 2 + s) * span * m0
            + (-2 * s ** 3 + 3 * s ** 2) * v1 + (s ** 3 - s ** 2) * span * m1)


def _channel(times, values, frames, loop, eases):
    """One channel's value on every frame: through the keys' `eases` (per move, the ease into its
    later key, or None for the smooth default)."""
    if len(times) == 1:
        return [values[0]] * len(frames)
    slopes = _tangents(times, values, loop, [ease is not None for ease in eases])
    out, key = [], 0
    for frame in frames:
        while key < len(times) - 2 and frame > times[key + 1]:
            key += 1
        ease = eases[key]
        if ease is None:
            out.append(_hermite(times[key], times[key + 1], values[key], values[key + 1], slopes[key],
                                slopes[key + 1], frame))
        else:
            share = EASES[ease]((frame - times[key]) / (times[key + 1] - times[key]))
            out.append(values[key] + (values[key + 1] - values[key]) * share)
    return out


def fill(poses, loop):
    """Every frame from the first key to the last, each channel interpolated through its keys
    (`poses`: [(frame, pose)], a key optionally naming its ease, (frame, pose, ease), see
    ease_of). A bone or axis a key leaves out is at rest there. Returns [(frame, pose)]."""
    times = [key[0] for key in poses]
    frames = list(range(times[0], times[-1] + 1))
    names = sorted({name for key in poses for name in key[1]})
    filled = [{} for _frame in frames]
    for name in names:
        eases = [ease_of(key, name) for key in poses[1:]]
        axes = [_channel(times, [key[1].get(name, (0.0, 0.0, 0.0))[axis] for key in poses], frames, loop, eases)
                for axis in range(3)]
        for index, pose in enumerate(filled):
            pose[name] = tuple(axes[axis][index] for axis in range(3))
    return list(zip(frames, filled))


class Shiver:
    """A shiver (#1074): `bones` tremble from frame `start` to `end`, quickly growing and dying
    away, about `hz` times a second and at most `amplitude` radians, as waves at unrelated rates
    on two axes, each bone out of step with the others. No noise generator, so a rebuild gives
    the same file. For one-shot clips only: it fades to nothing at both ends rather than meeting
    itself at a loop's seam."""

    def __init__(self, bones, start, end, amplitude, hz=7.0):
        self.bones, self.start, self.end, self.amplitude, self.hz = bones, start, end, amplitude, hz

    def __call__(self, poses, fps):
        """Adds the shiver to `poses` ([(frame, pose)], every frame, as `fill` gives them)."""
        for frame, pose in poses:
            if not self.start < frame < self.end:
                continue
            u = (frame - self.start) / (self.end - self.start)
            # Up to its peak a quarter of the way in, then dying away (u (1 - u)^3, peaking at 1).
            envelope = u * (1.0 - u) ** 3 / (0.25 * 0.75 ** 3) * self.amplitude
            t = 2.0 * math.pi * self.hz * (frame - self.start) / fps
            for index, bone in enumerate(self.bones):
                phase = 1.3 * index
                x, y, z = pose.get(bone, (0.0, 0.0, 0.0))
                bend = (math.sin(t + phase) + 0.4 * math.sin(1.71 * t + 2.0 * phase)) / 1.4
                sway = math.sin(0.83 * t + phase + 1.1)
                pose[bone] = (x + envelope * bend, y, z + envelope * sway)
        return poses


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
    """What `follow` and legs.plant need to know of an armature: each bone's parent, its rest
    matrix and orientation in the armature and its length and direction there, read once from the
    rig's bones."""

    def __init__(self, armature):
        self.parent = {bone.name: bone.parent.name if bone.parent else None for bone in armature.data.bones}
        self.matrix = {bone.name: bone.matrix_local.copy() for bone in armature.data.bones}
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
