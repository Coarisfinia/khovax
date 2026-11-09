"""Legs that plant their paws (#1073): on every frame each leg reaches for where its paw should
be, by a small analytic inverse kinematics, and the answer is plain rotations, keyed like any
other bone. No IK constraint, helper bone or bake reaches the export.

A clip says where each paw is with a "plant.<paw bone>" channel: the paw's (sideways, up,
forward) shift from where it stands at rest, in the model's unscaled metres, like "root_loc". A
paw no channel moves stays where it stands at rest, whatever the body does, so it never slides.
The paw bone's own rotation turns it from its rest in the world about its toes' tip (about world
X: positive tips its toes down and lifts its heel), so a planted paw stays flat on the ground
while the leg turns over it.

- `Leg`: which bones reach for a paw: an upper and a lower bone that bend between them, and
  optionally a follower below them that either turns with the upper one, as a hind leg's hock
  stays near parallel to its thigh (a pantograph), or swings as far as the whole leg does, as a
  foreleg's forearm stays in line with its swing while the shoulder takes up its length. Either
  way every leg is a closed-form solve. The follower's own rotation in a pose folds it further
  (about the leg's side axis: positive swings its end back). A leg bends in the plane that faces
  the body's side, unless it names its own (`plane`, the normal of the plane its bones lie in at
  rest): a leg whose knee bends out to the side, as a rib walking on its tip (#1476). The upper
  and the lower "bone" may each be several bones in a row that turn as one (#1539): a tentacle's
  many bones bend at the one joint between them, each keeping its rest curve.
- `steps`: a one-shot clip's steps, each an eased arc from where the paw stands to a new spot,
  lifted on the way, laid over the clip's frames as plant channels.
- `plant`: solves every leg on every frame of a clip and writes the bones' rotations into it.
"""

import math

from mathutils import Euler, Matrix, Vector

# How far (metres, scaled) a leg may fall short of a paw on the ground before the build fails.
REACH_TOLERANCE = 0.005
# The share of a step at its start a paw only rises, and at its end only comes down.
LIFT_SHARE = 0.15
# How far a leg may stretch, as a share of its full reach: a leg pulled straight turns wildly for
# a small move of its paw, so the body comes down instead (`plant`'s sinks).
STRETCH = 0.92


class Leg:
    """`upper` and `lower` are a bone's name each, or a tuple of bones in a row that turn as one."""

    def __init__(self, upper, lower, paw, follower=None, follows=True, plane=None):
        self.upper, self.lower, self.paw, self.follower, self.follows = upper, lower, paw, follower, follows
        self.plane = plane
        self.uppers = (upper,) if isinstance(upper, str) else tuple(upper)
        self.lowers = (lower,) if isinstance(lower, str) else tuple(lower)
        if plane is None and len(self.uppers + self.lowers) > 2:
            raise ValueError("a leg of bones in a row bends in its own plane: give it one")


class Step:
    """`paw` lifts at `start`, `height` metres at the top of its arc, and lands at `end` on
    `spot`, its (sideways, up, forward) shift from rest, where it stays until its next step."""

    def __init__(self, paw, start, end, spot, height):
        self.paw, self.start, self.end, self.spot, self.height = paw, start, end, spot, height


def ease(s):
    """0 to 1 as `s` goes 0 to 1 (clamped), starting and stopping with no speed and no
    acceleration: a paw's path joins its standing still or running with the ground without a
    jolt, in its joints too (smootherstep)."""
    s = min(1.0, max(0.0, s))
    return s * s * s * (s * (6.0 * s - 15.0) + 10.0)


def bump(s):
    """0 at `s` 0 and 1, 1 halfway, leaving and returning to 0 with no speed and no acceleration."""
    s = min(1.0, max(0.0, s))
    return 64.0 * (s * (1.0 - s)) ** 3


def steps(poses, made):
    """Lays `made` (Steps, each paw's in order) over `poses` ([(frame, pose)], every frame) as
    plant channels: forward and sideways ease in and out, after the paw has risen and before it
    comes down, so it leaves and lands without sliding, and it rises and falls smoothly (`ease`,
    `bump`). A paw starts where the clip's first pose plants it (a clip that plays on from
    another one's stance), at rest without one."""
    for paw in sorted({step.paw for step in made}):
        spot, frames = tuple(poses[0][1].get("plant." + paw, (0.0, 0.0, 0.0))), []
        for step in sorted((step for step in made if step.paw == paw), key=lambda step: step.start):
            frames.append((step, spot))
            spot = step.spot
        for frame, pose in poses:
            here = (0.0, 0.0, 0.0)
            for step, before in frames:
                if frame >= step.end:
                    here = step.spot
                elif frame > step.start:
                    s = (frame - step.start) / (step.end - step.start)
                    # It lifts before it moves and moves before it comes down: it leaves the
                    # ground and lands straight up and down.
                    along = ease((s - LIFT_SHARE) / (1.0 - 2.0 * LIFT_SHARE))
                    here = tuple(a + (b - a) * along for a, b in zip(before, step.spot))
                    here = (here[0], here[1] + step.height * bump(s), here[2])
                    break
                else:
                    here = before
                    break
            pose["plant." + paw] = here
    return poses


def posed(rig, pose, name, scale, cache):
    """A bone's posed matrix in the armature (its rest, turned by its parents and itself)."""
    if name not in cache:
        basis = Euler(pose.get(name, (0.0, 0.0, 0.0)), "XYZ").to_matrix().to_4x4()
        parent = rig.parent[name]
        if parent is None:
            shift = Vector(pose.get("root_loc", (0.0, 0.0, 0.0))) * scale
            cache[name] = rig.matrix[name] @ Matrix.Translation(shift) @ basis
        else:
            above = posed(rig, pose, parent, scale, cache) @ rig.matrix[parent].inverted()
            cache[name] = above @ rig.matrix[name] @ basis
    return cache[name]


def _flat(vector):
    """A rest bone in its leg's plane: (down, back), at its full length."""
    return Vector((-vector.z, vector.y)).normalized() * vector.length


def _in_plane(normal):
    """`_flat` for a leg in its own plane (Leg's `plane`): a rest bone as (down, back) in that
    plane, down being straight down seen in it and back across it from the plane's normal."""
    normal = normal.normalized()
    down = Vector((0.0, 0.0, -1.0))
    down = (down - down.project(normal)).normalized()
    back = normal.cross(down)
    return lambda vector: Vector((vector.dot(down), vector.dot(back)))


def _turned(vector, angle):
    c, s = math.cos(angle), math.sin(angle)
    return Vector((c * vector.x - s * vector.y, s * vector.x + c * vector.y))


def _cross(a, b):
    return a.x * b.y - a.y * b.x


def _bend(reach, upper, lower, follower):
    """The leg in its plane: the angle the upper bone (and its follower) turns by and the lower
    bone's direction, so the chain ends on `reach` and bends the way it does at rest. Past
    STRETCH of its full reach it eases toward straight and falls short instead (a soft IK): a
    leg snapping straight would flip its joints from one frame to the next."""
    whole = upper + follower
    length = lower.length
    distance, span = max(reach.length, 1e-6), max(whole.length, 1e-6)
    full = span + length
    if distance > STRETCH * full:
        soft = (1.0 - STRETCH) * full
        distance = full - soft * math.exp(-(distance - STRETCH * full) / soft)
        reach = reach.normalized() * distance
    cosine = (distance * distance + span * span - length * length) / (2.0 * distance * span)
    opening = math.acos(max(-1.0, min(1.0, cosine)))
    aim = math.atan2(reach.y, reach.x) - math.atan2(whole.y, whole.x)
    side = _cross(upper, lower)
    for angle in (aim + opening, aim - opening):
        rest = reach - _turned(whole, angle)
        if _cross(_turned(upper, angle), rest) * side >= 0.0:
            break
    if rest.length < 1e-6:
        rest = _turned(lower, angle)
    return angle, rest.normalized() * length


def _swing(base, direction):
    """`base` (a bone's orientation under its posed parent) turned the shortest way so its Y
    axis points along `direction`: no twist about the bone."""
    along = base.col[1].normalized()
    return along.rotation_difference(direction.normalized()).to_matrix() @ base


def _solve(rig, pose, leg, scale, cache, rise):
    """The leg's bones' orientations reaching its paw's target, how far short they fall while it's
    on the ground, and how far its top would have to come down for it to reach there without
    stretching past STRETCH."""
    first = leg.uppers[0]
    parent = rig.parent[first]
    carry = posed(rig, pose, parent, scale, cache) @ rig.matrix[parent].inverted()
    turn = carry.to_3x3()
    top = (carry @ rig.matrix[first]).translation
    side, up, forward = pose.get("plant." + leg.paw, (0.0, 0.0, 0.0))
    # The paw tilts about its toes' tip: tipping its toes down lifts its heel, so it peels off
    # the ground from the heel and lands toes first, never sliding.
    tilt = Euler(pose.get(leg.paw, (0.0, 0.0, 0.0)), "XYZ").to_matrix()
    tip = rig.matrix[leg.paw].translation + rig.vector[leg.paw]
    target = tip + Vector((side, -forward, up)) * scale - tilt @ rig.vector[leg.paw] + Vector((0.0, 0.0, rise))
    reach = target - top
    # The leg bends in the plane through its top and its target that faces the body's side, or
    # its own plane's, turned with the body.
    flatten = _flat if leg.plane is None else _in_plane(Vector(leg.plane))
    normal = turn @ Vector((1.0, 0.0, 0.0) if leg.plane is None else leg.plane)
    normal = (normal - normal.project(reach)).normalized()
    down = turn @ Vector((0.0, 0.0, -1.0))
    down = (down - down.project(normal)).normalized()
    back = normal.cross(down)

    def solid(flat):
        return down * flat.x + back * flat.y

    # A bone of several in a row keeps its reach out of the leg's plane, turned with the leg; the
    # bones of each run end in the plane (Leg's `plane` runs through its top, knee and paw).
    rest = Vector(leg.plane).normalized() if leg.plane is not None else None

    def bent(names, angle):
        if len(names) == 1:
            return [(names[0], solid(_turned(flatten(rig.vector[names[0]]), angle)))]
        return [(name, solid(_turned(flatten(rig.vector[name]), angle)) + normal * rig.vector[name].dot(rest))
                for name in names]

    upper = sum((flatten(rig.vector[name]) for name in leg.uppers[1:]), flatten(rig.vector[first]))
    lower = sum((flatten(rig.vector[name]) for name in leg.lowers[1:]), flatten(rig.vector[leg.lowers[0]]))
    flat = Vector((reach.dot(down), reach.dot(back)))
    follower = Vector((0.0, 0.0))
    if leg.follower:
        fold = pose.get(leg.follower, (0.0, 0.0, 0.0))[0]
        if not leg.follows:
            # It swings as far as the whole leg does from its rest, toward where its paw is over
            # the ground (a lifted paw comes up close under the leg, where the way to it turns
            # fast: the lift is the other bones' to take up).
            still = flatten(rig.matrix[leg.paw].translation - rig.matrix[first].translation)
            over = reach - Vector((0.0, 0.0, up * scale))
            toward = Vector((over.dot(down), over.dot(back)))
            fold += math.atan2(toward.y, toward.x) - math.atan2(still.y, still.x)
        follower = _turned(flatten(rig.vector[leg.follower]), fold)
    if leg.follows:
        angle, shin = _bend(flat, upper, lower, follower)
        held = _turned(follower, angle)
        longest, left = STRETCH * ((upper + follower).length + lower.length), reach
    else:
        # The follower points the way the leg swings: the two bones above it reach for its top.
        angle, shin = _bend(flat - follower, upper, lower, Vector((0.0, 0.0)))
        held = follower
        longest, left = STRETCH * (upper.length + lower.length), reach - solid(follower)
    across = left.x * left.x + left.y * left.y
    # Only a paw on the ground needs the body to come down to it; one in the air may fall short.
    grounded = up <= 0.0
    sink = max(0.0, -left.z - math.sqrt(max(0.0, longest * longest - across))) if grounded else 0.0
    if len(leg.lowers) == 1:
        lowered = [(leg.lowers[0], solid(shin))]
    else:
        lowered = bent(leg.lowers, math.atan2(shin.y, shin.x) - math.atan2(lower.y, lower.x))
    chain = bent(leg.uppers, angle) + lowered
    if leg.follower:
        chain.append((leg.follower, solid(held)))
    # Each bone swings the shortest way from its rest under its posed parent, so it never twists.
    out, above, end = {}, (parent, turn @ rig.matrix[parent].to_3x3()), top
    for name, direction in chain:
        base = above[1] @ rig.matrix[above[0]].to_3x3().inverted() @ rig.matrix[name].to_3x3()
        out[name] = _swing(base, direction)
        above, end = (name, out[name]), end + direction
    # The paw keeps its turn in the world, whatever the leg above it does.
    out[leg.paw] = tilt @ rig.matrix[leg.paw].to_3x3()
    return out, (target - end).length if grounded else 0.0, sink


def plant(rig, poses, legs, scale, rises=None):
    """Poses every leg of `legs` on every frame of `poses` ([(frame, pose)], every frame) so it
    reaches its paw's target: returns the poses with the bones' rotations written in (`poses`
    stays as it was), and the farthest any leg fell short of a paw on the ground (metres, scaled)
    with that paw: a target out of reach shows there; and per frame how far the body would have
    to come down (metres, scaled) for every leg to reach its paw on the ground unstretched. `rig`
    is a motion.Rig, `scale` the model's; `rises` raises each paw's spot (metres, scaled) off its
    rest, as onto the ground where it sinks into it at rest."""
    shortest, previous, out, sinks = (0.0, ""), {}, [], []
    for frame, planned in poses:
        pose, cache = dict(planned), {}
        sinks.append(0.0)
        for leg in legs:
            turns, short, sink = _solve(rig, planned, leg, scale, cache, (rises or {}).get(leg.paw, 0.0))
            shortest = max(shortest, (short, leg.paw))
            sinks[-1] = max(sinks[-1], sink)
            for name, turn in turns.items():
                # Each bone's turn is kept relative to its parent's: the leg's own, or the body's.
                parent = rig.parent[name]
                held = turns[parent] if parent in turns else posed(rig, planned, parent, scale, cache).to_3x3()
                base = held @ rig.matrix[parent].to_3x3().inverted() @ rig.matrix[name].to_3x3()
                local = (base.inverted() @ turn).to_euler("XYZ", previous.get(name, Euler()))
                previous[name] = local
                pose[name] = tuple(local)
        out.append((frame, pose))
    return out, shortest, sinks
