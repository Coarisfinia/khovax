"""A hexapod (#1476): six legs in three pairs, front, middle and hind, under a quadruped's trunk.
Its armature is the quadruped's trunk (root, hips, a two-bone spine, neck, head and a tail chain,
the same names, so the creature clips that pose only the trunk play on it as they are) with three
bones a leg, thigh, shin and paw, named `<pair>_thigh.L` and so on. A leg bends in its own plane
(legs.Leg's `plane`), so a leg whose knee juts out to the side, like a spider's or a rib walked on
its tip, keeps its bend as it reaches.

Its gaits plant every paw (legs), and its skin is weighted by where it lies (`bind`): a body of
thin pieces close together (ribs over a hollow) leaves automatic weights no room to tell a leg
from the rib beside it. Blender is Z-up and the animal faces -Y."""

import math

import bpy
from mathutils import Vector

from . import clips, legs, quadruped, scene

PAIRS = ("front", "mid", "hind")
# The trunk bone each pair hangs from.
HUNG_FROM = {"front": "spine_02", "mid": "spine_01", "hind": "hips"}
SIDES = (("L", lambda point: point), ("R", quadruped.mirrored))


class Proportions:
    """Where a hexapod's joints are, in metres, for its left side (the right mirrors across X).

    - `tail`: tip first; its first bone runs from the hips to its last point.
    - `hips`, `waist` (where the spine bends), `chest`, `head_base`, `nose`.
    - `legs`: {pair: [hip, knee, ankle, paw tip]} for each of PAIRS.
    """

    def __init__(self, **joints):
        for name, value in joints.items():
            setattr(self, name, value)


def bone(pair, part, side):
    return "%s_%s.%s" % (pair, part, side)


def bones(p):
    """(name, head, tail, parent) for every bone."""
    out = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.3), None),
        ("hips", p.hips, p.waist, "root"),
        ("spine_01", p.waist, _between(p.waist, p.chest), "hips"),
        ("spine_02", _between(p.waist, p.chest), p.chest, "spine_01"),
        ("neck", p.chest, p.head_base, "spine_02"),
        ("head", p.head_base, p.nose, "neck"),
    ]
    parent, previous = "hips", p.hips
    for index, point in enumerate(reversed(p.tail)):
        name = "tail_%02d" % (index + 1)
        out.append((name, previous, point, parent))
        parent, previous = name, point
    for side, flip in SIDES:
        for pair in PAIRS:
            points = [flip(point) for point in p.legs[pair]]
            above = HUNG_FROM[pair]
            for index, part in enumerate(("thigh", "shin", "paw")):
                out.append((bone(pair, part, side), points[index], points[index + 1], above))
                above = bone(pair, part, side)
    return out


def armature(name, proportions):
    return quadruped.build(name, bones(proportions))


def plane(points):
    """The normal of the plane a leg's hip, knee and ankle lie in."""
    hip, knee, ankle = (Vector(point) for point in points[:3])
    return tuple((knee - hip).cross(ankle - knee).normalized())


def limbs(p):
    """Every leg for legs.plant, each bending in its own plane."""
    return [legs.Leg(bone(pair, "thigh", side), bone(pair, "shin", side), bone(pair, "paw", side),
                     plane=plane([flip(point) for point in p.legs[pair]]))
            for side, flip in SIDES for pair in PAIRS]


# Overlap and follow-through (motion.follow): the quadruped's neck, head and tail.
FOLLOW = {name: clips.FOLLOW[name] for name in ("neck", "head", "tail_01", "tail_02", "tail_03", "tail_04")}

# The legs' phases in a cycle, as (pair, side): 0..1. A walk is a wave running up each side from
# the hind leg to the front one, the two sides half a cycle apart, so at least four legs stand at
# once; a run is the tripod, the front and hind legs of one side and the middle one of the other
# moving together.
WAVE = {("hind", "L"): 0.0, ("mid", "L"): 1.0 / 3.0, ("front", "L"): 2.0 / 3.0,
        ("hind", "R"): 0.5, ("mid", "R"): 5.0 / 6.0, ("front", "R"): 1.0 / 6.0}
TRIPOD = {("front", "L"): 0.0, ("mid", "R"): 0.0, ("hind", "L"): 0.0,
          ("front", "R"): 0.5, ("mid", "L"): 0.5, ("hind", "R"): 0.5}


def crouch(height):
    """An `animate` overlay that lowers the body `height` (unscaled metres) in every clip: a leg
    standing nearly straight in its rest pose (a rib walked on its tip) turns its knee wildly for
    a small move of its paw (legs.STRETCH), and bent a little further it reaches smoothly."""
    def lower(_name, poses, _loop):
        for _frame, pose in poses:
            x, y, z = pose.get("root_loc", (0.0, 0.0, 0.0))
            pose["root_loc"] = (x, y - height, z)
    return lower


def gait(frames, stride, body, phases, duty, lift=0.2, bob=0.02, roll=0.03, sway=0.15):
    """A looping gait, posed on every frame: each paw is planted for `duty` of the cycle, running
    back `stride` x `duty` at the body's speed (`stride`: unscaled metres the body moves in one
    cycle) about the spot under its hip, then lifts (`lift` of its leg's reach at the top) and
    swings forward at its phase;
    the legs reach for their paws (legs.plant). The body sinks `bob` (unscaled metres) as each
    group of legs takes its weight, rolls `roll` (radians) toward the side bearing more of it,
    the head countering the roll, and the tail sways `sway` radians once a cycle."""
    reaches = {pair: clips._leg(body.legs[pair])[0] for pair in PAIRS}
    # How far each paw stands ahead of its hip at rest: its steps sweep about the spot under the
    # hip instead, so a leg leaning forward doesn't reach past straight at the front of its step.
    leans = {pair: body.legs[pair][0][1] - body.legs[pair][-1][1] for pair in PAIRS}
    sweep = stride * duty
    beats = round(1.0 / min(abs(a - b) or 1.0 for a in phases.values() for b in phases.values()))
    poses = []
    for step in range(frames + 1):
        t = step / frames
        pose, bearing = {}, 0.0
        for (pair, side), phase in phases.items():
            u = (t - phase) % 1.0
            ahead, up = clips._step(u, duty, sweep, clips.MATCHED * duty / (1.0 - duty))
            pose["plant." + bone(pair, "paw", side)] = (0.0, lift * reaches[pair] * up, ahead - leans[pair])
            if u < duty:
                bearing += (1.0 if side == "L" else -1.0) * math.sin(math.pi * u / duty)
        lap = 2.0 * math.pi * t
        tilt = roll * bearing / 3.0
        pose.update({
            "root_loc": (0.0, -bob * (0.5 - 0.5 * math.cos(beats * lap)), 0.0),
            "hips": (0.0, -tilt, 0.0),
            "spine_02": (0.0, -0.5 * tilt, 0.0),
            "neck": (0.0, 0.0, 0.5 * tilt),
            "head": (0.0, 1.2 * tilt, 0.0),
            "tail_01": (0.05, 0.0, sway * math.sin(lap)),
            "tail_02": (0.0, 0.0, sway * math.sin(lap - 0.8)),
        })
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True)


def scurry(frames, phases, swing, lift, skim, bounce=0.02, roll=0.03, sway=0.2):
    """A run too fast for planted paws (#1073), posed on every frame as smooth waves: each leg
    swings from its hip, back `swing` radians and forward as far, at its phase, raised `lift`
    radians out to the side as it swings forward; the body skims `skim` (unscaled metres) up, so
    its paws pass over the ground rather than slide on it (a clip plays in place: the game moves
    the model), bouncing `bounce` higher between the beats of its feet and rolling `roll` toward
    the side bearing it; the tail sways `sway` radians once a cycle."""
    beats = round(1.0 / min(abs(a - b) or 1.0 for a in phases.values() for b in phases.values()))
    poses = []
    for step in range(frames + 1):
        t = step / frames
        lap = 2.0 * math.pi * t
        pose = {}
        for (pair, side), phase in phases.items():
            turn = 2.0 * math.pi * (t - phase)
            # Back while it bears (the first half of its cycle), forward and raised while it swings.
            raised = lift * max(0.0, -math.cos(turn)) ** 2
            pose[bone(pair, "thigh", side)] = (swing * math.sin(turn), 0.0, -raised if side == "L" else raised)
        tilt = roll * math.sin(lap - 2.0 * math.pi * phases["front", "L"])
        pose.update({
            "root_loc": (0.0, skim + bounce * (0.5 - 0.5 * math.cos(beats * lap)), 0.0),
            "hips": (0.0, -tilt, 0.0),
            "spine_02": (0.0, -0.5 * tilt, 0.0),
            "head": (0.0, 1.2 * tilt, 0.0),
            "tail_01": (0.1, 0.0, sway * math.sin(lap)),
            "tail_02": (0.0, 0.0, sway * math.sin(lap - 0.8)),
        })
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)


def softened(clip, share):
    """`clip` with the root's every shift `share` as large: a sharp move of the body asks a leg
    standing nearly straight to turn its knee too fast."""
    keys = []
    for key in clip.keys:
        pose = dict(key[1])
        if "root_loc" in pose:
            pose["root_loc"] = tuple(share * value for value in pose["root_loc"])
        keys.append((key[0], pose, *key[2:]))
    clip.keys = keys
    return clip


def spread(steps_out, spots, start, late=1, length=10, height=0.06):
    """Each paw's step to `spots` ({pair: its left one's (sideways, up, forward)}, the right
    mirrored), pair after pair from `start`, `late` frames apart, the right a frame after the
    left; with `steps_out` False, back to where it stands."""
    made = []
    for index, pair in enumerate(spots):
        side, up, forward = spots[pair] if steps_out else (0.0, 0.0, 0.0)
        for name, sign, after in (("L", 1.0, 0), ("R", -1.0, 1)):
            begin = start + index * late + after
            made.append(legs.Step(bone(pair, "paw", name), begin, begin + length, (sign * side, up, forward), height))
    return made


def paws(spots):
    """`spots` ({pair: its left paw's shift}) keyed by paw as the library's clips take them
    (clips.channel's `brace`, clips.sleep's `paws`): {"front_paw": shift, ...}."""
    return {"%s_paw" % pair: spot for pair, spot in spots.items()}


def faint(body_height, paws):
    """The legs give way (#1074): it staggers, catches itself once, then sinks `body_height`
    down, its paws stepping out to `paws` ({pair: shift}) one pair after another so its legs fold
    out to the sides, its head knocking onto the ground and bouncing once, and it keeps sinking
    into the ground's hold rather than freezing there."""
    stagger = {"root_loc": (0, -body_height * 0.08, 0), "spine_02": (0, 0.05, 0.04), "neck": (0.12, 0, 0),
               "head": (0.1, -0.1, 0)}
    caught = {"root_loc": (0, -body_height * 0.03, 0), "spine_02": (0, -0.03, -0.02), "head": (-0.04, 0.06, 0)}
    sinking = {"root_loc": (0, -body_height * 0.5, 0), "neck": (0.15, 0, 0), "head": (0.1, 0.08, 0)}
    down = {"root_loc": (0, -body_height * 0.95, 0), "neck": (0.3, 0, 0), "head": (0.2, 0.15, 0),
            "tail_01": (0.35, 0, 0.25), "tail_02": (0.1, 0, 0.25)}
    bounce = dict(down, neck=(0.24, 0, 0), head=(0.16, 0.13, 0))
    still = dict(down, root_loc=(0, -body_height, 0), neck=(0.32, 0, 0), head=(0.22, 0.17, 0))
    return clips.Clip([(1, {}), (6, stagger), (10, caught), (20, sinking), (32, down), (35, bounce, "quart"),
                       (39, down), (52, still)], steps=spread(True, paws, 12, late=2, length=14))


def sleeping(body_height):
    """Its sleeping pose (#1229), at `chest` (0..1) of a breath: lying `body_height` down as its
    faint leaves it, its head on the ground turned a little, its tail curled round to one side;
    the breath swells its back."""
    def pose(chest):
        return {"root_loc": (0.0, -body_height * 0.98, 0.0), "spine_02": (0.03 * chest, 0.0, 0.02),
                "spine_01": (-0.02 * chest, 0.0, 0.03), "neck": (0.3 - 0.03 * chest, 0.0, 0.1),
                "head": (0.2, 0.1, 0.12), "tail_01": (0.3, 0.0, 0.4), "tail_02": (0.05, 0.0, 0.5),
                "tail_03": (0.0, 0.0, 0.5), "tail_04": (0.0, 0.0, 0.4 + 0.03 * chest)}
    return pose


# How far around a leg's bones (unscaled metres) its skin lies, and over how much height about
# the hip the skin passes from the trunk to the leg.
LEG_RADIUS, HIP_BLEND = 0.08, 0.05
# How far around the tail's bones its skin lies (unscaled metres).
TAIL_RADIUS = 0.1


def _distance(point, head, tail):
    along = tail - head
    share = max(0.0, min(1.0, (point - head).dot(along) / along.length_squared))
    return (point - (head + along * share)).length


def _smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def bind(skin, rig, scale):
    """Weights `skin` to `rig` by where each vertex lies, in plain Python floats so every machine
    gives the same weights: near a leg's bones and below its hip it is the leg's, blended between
    its bones by how near each is; near the tail's bones and behind the hips the tail's; the rest
    is the trunk's (hips, spine, neck and head), blended between the two bones whose middles lie
    either side of it along the body. `scale` is the model's (scene.apply_scale)."""
    scene.select_only(skin)
    skin.parent = rig
    skin.modifiers.new("Armature", "ARMATURE").object = rig
    to_rig = rig.matrix_world.inverted() @ skin.matrix_world
    bones = rig.data.bones
    groups = {}

    def group(name):
        if name not in groups:
            groups[name] = skin.vertex_groups.new(name=name)
        return groups[name]

    trunk = sorted(((bones[name].head_local.y + bones[name].tail_local.y) / 2.0, name)
                   for name in ("hips", "spine_01", "spine_02", "neck", "head"))
    tail = sorted((name for name in bones.keys() if name.startswith("tail_")))
    leg_bones = [[bone(pair, part, side) for part in ("thigh", "shin", "paw")] for side, _flip in SIDES for pair in PAIRS]
    radius, blend, tail_radius = LEG_RADIUS * scale, HIP_BLEND * scale, TAIL_RADIUS * scale
    for vertex in skin.data.vertices:
        point = to_rig @ vertex.co
        shares = {}
        rest = 1.0
        for chain in leg_bones:
            spans = [(bones[name].head_local, bones[name].tail_local) for name in chain]
            nearest = [_distance(point, head, tail_) for head, tail_ in spans]
            if min(nearest) > radius:
                continue
            hip = spans[0][0].z
            taken = rest * _smooth((hip + blend - point.z) / (2.0 * blend))
            if taken <= 0.0:
                continue
            pulls = [1.0 / (distance + 0.01 * scale) ** 6 for distance in nearest]
            whole = sum(pulls)
            for name, pull in zip(chain, pulls):
                shares[name] = shares.get(name, 0.0) + taken * pull / whole
            rest -= taken
            break
        if rest > 0.0 and point.y > trunk[-1][0]:
            spans = [(bones[name].head_local, bones[name].tail_local) for name in tail]
            nearest = [_distance(point, head, tail_) for head, tail_ in spans]
            if min(nearest) <= tail_radius:
                pulls = [1.0 / (distance + 0.01 * scale) ** 6 for distance in nearest]
                # The tail's root blends into the hips.
                taken = rest * _smooth((point.y - trunk[-1][0]) / (bones["tail_01"].length * 0.5))
                whole = sum(pulls)
                for name, pull in zip(tail, pulls):
                    shares[name] = shares.get(name, 0.0) + taken * pull / whole
                rest -= taken
        if rest > 0.0:
            for (start, first), (end, second) in zip(trunk, trunk[1:]):
                if point.y <= end:
                    along = max(0.0, min(1.0, (point.y - start) / (end - start)))
                    shares[first] = shares.get(first, 0.0) + rest * (1.0 - along)
                    shares[second] = shares.get(second, 0.0) + rest * along
                    break
            else:
                shares[trunk[-1][1]] = shares.get(trunk[-1][1], 0.0) + rest
        for name, share in sorted(shares.items()):
            if share > 0.0:
                group(name).add([vertex.index], share, "REPLACE")
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)


def _between(a, b):
    return tuple((x + y) / 2 for x, y in zip(a, b))
