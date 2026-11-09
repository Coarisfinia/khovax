"""A limbless body (#1737): a round body with a head and, optionally, a tail, that moves without
legs, as a tadpole wriggles over the ground. The bud (#1738) and any other legless beast can take
it as its body plan: quadruped and hexapod plant paws, this one has none to plant.

- `armature`: root, `spine_01` (the body, from its back to the head's base, pointing forward),
  `head` (to the snout's tip) and a tail chain `tail_01`, `tail_02`, ... hung from the body's back,
  each bone rolled as quadruped's are (turning about X bends it: the head's nose and the tail's
  tip go down for a positive turn of the head and up for the tail's; about Z it sways).
- `bind`: the skin weighted by where each vertex lies along the body, from the head's tip to the
  tail's, blended between the bones whose middles lie either side of it. A generated mesh's seam
  splits (the model skill's traps) lie on the same spot, so they take the same weights.
- The clips, every creature clip (lib/clip_set.py) posed on the trunk alone, unplanted (`Clip`'s
  `planted=False`): `idle`, `wriggle` (Walk and Run: a wave running down the body to the tail's
  tip, the body hopping along), `attack`, `hit`, `faint` (it tips over onto its side), `channel`,
  `feed` and `sleep`. A body without a tail leaves its tail's keys out (`Clip` keys for bones it
  lacks are never keyed: lib/clips.py keys only the rig's bones).

Blender is Z-up and the body faces -Y. A pose's "root" turns the whole body about its feet: about
X it pitches (positive: nose down), about Z, the root's forward axis, it rolls onto its side."""

import math

import bpy
from mathutils import Vector

from . import clips, motion, scene

BODY, HEAD = "spine_01", "head"
# How long the root bone is (metres): it deforms nothing.
ROOT_LENGTH = 0.3


def tail(count):
    """The tail's bones, from its root to its tip."""
    return ["tail_%02d" % (index + 1) for index in range(count)]


class Body:
    """Where a limbless body's joints are, in metres: `nose` (the head's tip), `head_base` (where
    the head meets the body), `back` (the body's back end, where a tail hangs) and `tail`, the
    tail's joints from its root to its tip (none for a body without one)."""

    def __init__(self, nose, head_base, back, tail=()):
        self.nose, self.head_base, self.back, self.tail = nose, head_base, back, list(tail)


def scaled(body, scale):
    """`body` with every joint `scale` times as far from the origin."""
    def at(point):
        return tuple(scale * value for value in point)

    return Body(at(body.nose), at(body.head_base), at(body.back), [at(point) for point in body.tail])


def bones(body):
    """(name, head, tail, parent) for every bone of `body`."""
    out = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, ROOT_LENGTH), None),
        (BODY, body.back, body.head_base, "root"),
        (HEAD, body.head_base, body.nose, BODY),
    ]
    parent, previous = BODY, body.back
    for name, point in zip(tail(len(body.tail)), body.tail):
        out.append((name, previous, point, parent))
        parent, previous = name, point
    return out


def armature(name, body):
    """The armature of `body`, its bones rolled so their local X is world X (quadruped's way)."""
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(rig)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail_, parent in bones(body):
        bone = data.edit_bones.new(bone_name)
        bone.head, bone.tail = Vector(head), Vector(tail_)
        if parent is not None:
            bone.parent = data.edit_bones[parent]
            direction = (bone.tail - bone.head).normalized()
            bone.align_roll(Vector((1.0, 0.0, 0.0)).cross(direction))
        else:
            bone.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _smooth(share):
    share = max(0.0, min(1.0, share))
    return share * share * (3.0 - 2.0 * share)


def bind(skin, rig):
    """Weights `skin` to `rig` by where each vertex lies along the body (its Y), in plain Python
    floats so every machine gives the same weights: between the middles of the two bones either
    side of it, blended smoothly from one to the other; in front of the head's middle all the
    head's, behind the tail's last bone's middle all its."""
    scene.select_only(skin)
    skin.parent = rig
    skin.modifiers.new("Armature", "ARMATURE").object = rig
    to_rig = rig.matrix_world.inverted() @ skin.matrix_world
    names = [bone.name for bone in rig.data.bones if bone.use_deform]
    middles = sorted(((bone.head_local.y + bone.tail_local.y) / 2.0, bone.name)
                     for bone in rig.data.bones if bone.name in names)
    groups = {name: skin.vertex_groups.new(name=name) for _middle, name in middles}
    for vertex in skin.data.vertices:
        y = (to_rig @ vertex.co).y
        if y <= middles[0][0]:
            groups[middles[0][1]].add([vertex.index], 1.0, "REPLACE")
            continue
        if y >= middles[-1][0]:
            groups[middles[-1][1]].add([vertex.index], 1.0, "REPLACE")
            continue
        for (start, first), (end, second) in zip(middles, middles[1:]):
            if y <= end:
                along = _smooth((y - start) / (end - start))
                if along < 1.0:
                    groups[first].add([vertex.index], 1.0 - along, "REPLACE")
                if along > 0.0:
                    groups[second].add([vertex.index], along, "REPLACE")
                break


def follow(count):
    """motion.follow's chains for a tail of `count` bones: each trails the one before it, looser
    toward the tip, so a wave or a whip runs on down it (as quadruped's tail, clips.FOLLOW)."""
    return {name: (max(1.6, 2.8 * 0.88 ** index), max(0.35, 0.5 - 0.04 * index), 0.0, 0.1)
            for index, name in enumerate(tail(count))}


def _wave(pose, count, lap, amplitude, lag, grow=0.35, lift=0.0):
    """A sideways wave down the tail at `lap` (radians): each bone turned about Z by `amplitude`
    (radians at its root, `grow` more for each bone toward the tip), `lag` radians behind the one
    before it, and raised `lift` radians (about X)."""
    for index, name in enumerate(tail(count)):
        x, y, z = pose.get(name, (0.0, 0.0, 0.0))
        sway = amplitude * (1.0 + grow * index) * math.sin(lap - lag * (index + 1))
        pose[name] = (x + lift, y, z + sway)
    return pose


def _tail(count, pose, values):
    """Sets each of the tail's first bones to `values` (one (x, y, z) each, the last held for the
    rest of the tail), in place."""
    for index, name in enumerate(tail(count)):
        pose[name] = values[min(index, len(values) - 1)]
    return pose


def idle(count, breath=90, breaths=2):
    """Resting, alive: it breathes `breaths` times a loop of `breath` frames each (the body
    swelling up and settling, a breath in quicker than out), glances about with its head, and its
    tail sways lazily, the wave running down it once a breath. Posed on every frame, every wave a
    whole number of times a loop, so the seam is exact; the lids blink (eyes.Lids)."""
    frames = breath * breaths
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        chest = 0.5 - 0.5 * math.cos(breaths * lap) + 0.15 * math.sin(breaths * lap) * (1.0 - math.cos(breaths * lap))
        glance = math.sin(lap + 1.0)
        pose = {
            "root_loc": (0.0, 0.02 * chest, 0.0),
            BODY: (-0.03 * chest, 0.0, 0.03 * math.sin(lap)),
            HEAD: (0.04 * chest - 0.02 * math.sin(2.0 * lap), 0.0, 0.10 * glance),
        }
        _wave(pose, count, breaths * lap, 0.10, 0.8, lift=0.04)
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)


def wriggle(count, frames, sway, hop, surge=0.04, waves=1):
    """Moving on: a wave of `sway` radians runs down the tail `waves` times a loop of `frames`
    frames, the body and the head turning against it so the head stays on course, and the body
    hops `hop` metres off the ground twice a wave, pitching nose down as it lands and surging
    `surge` metres forward and back. Posed on every frame; the game moves it along."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * waves * (step % frames) / frames
        # Twice a wave, a lift that lingers a little in the air and lands quickly.
        bounce = math.sin(lap) ** 2
        pose = {
            "root_loc": (0.0, hop * bounce, surge * math.sin(2.0 * lap)),
            "root": (0.05 * math.sin(2.0 * lap - 0.6), 0.0, 0.0),
            BODY: (0.0, 0.0, -0.45 * sway * math.sin(lap)),
            HEAD: (-0.03 * bounce, 0.0, 0.25 * sway * math.sin(lap + 0.4)),
        }
        _wave(pose, count, lap, sway, 0.9, grow=0.3, lift=0.05 * bounce)
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)


def attack(count):
    """Anticipation, action, overshoot and settle (#1074): it draws back, head up and tail curled
    high, still drawing back as it holds; snaps forward into a lunge, a little off the ground, and
    butts with its head, the tail whipping after it; pulls back, sways past where it lies and
    settles."""
    drawn = _tail(count, {"root_loc": (0.0, 0.0, -0.25), "root": (-0.10, 0.0, 0.0), BODY: (-0.08, 0.0, 0.0),
                          HEAD: (-0.15, 0.0, 0.0)}, [(0.25, 0.0, 0.0), (0.2, 0.0, 0.0)])
    coiled = dict(drawn, root_loc=(0.0, 0.0, -0.29), root=(-0.12, 0.0, 0.0))
    lunge = _tail(count, {"root_loc": (0.0, 0.12, 0.55), "root": (0.08, 0.0, 0.0), BODY: (0.05, 0.0, 0.0),
                          HEAD: (0.10, 0.0, 0.0)}, [(-0.15, 0.0, 0.0), (-0.1, 0.0, 0.0)])
    butt = dict(lunge, root_loc=(0.0, 0.04, 0.62), root=(0.14, 0.0, 0.0), **{HEAD: (0.25, 0.0, 0.0)})
    back = _tail(count, {"root_loc": (0.0, 0.0, 0.12), "root": (0.0, 0.0, 0.0), HEAD: (0.05, 0.0, 0.0)},
                 [(0.08, 0.0, 0.0)])
    past = _tail(count, {"root_loc": (0.0, 0.0, -0.04), "root": (-0.02, 0.0, 0.0), HEAD: (-0.03, 0.0, 0.0)},
                 [(-0.04, 0.0, 0.0)])
    return clips.Clip([(1, {}), (8, drawn), (11, coiled), (17, lunge, "back"), (20, butt, "quart"),
                       (26, back, "quart"), (30, past), (36, {})], planted=False)


def hit(count):
    """Recoil from a blow (#1074): it snaps back, head up, the tail flung up, a shiver running
    through it; then it rebounds past where it lay and settles."""
    recoil = _tail(count, {"root_loc": (0.0, 0.03, -0.25), "root": (-0.12, 0.0, 0.05), BODY: (-0.06, 0.0, 0.08),
                           HEAD: (-0.2, 0.0, 0.1)}, [(0.3, 0.0, -0.2), (0.15, 0.0, -0.15)])
    reeling = dict(recoil, root_loc=(0.0, 0.03, -0.30), root=(-0.14, 0.0, 0.06))
    rebound = _tail(count, {"root_loc": (0.0, 0.0, 0.05), "root": (0.03, 0.0, -0.02), BODY: (0.02, 0.0, -0.03),
                            HEAD: (0.05, 0.0, -0.03)}, [(-0.08, 0.0, 0.1)])
    shiver = motion.Shiver([BODY, HEAD] + tail(count)[:1], 4, 18, math.radians(2.0))
    return clips.Clip([(1, {}), (4, recoil, "expo"), (8, reeling), (16, rebound), (26, {})], planted=False,
                      shiver=shiver)


# How far (radians) a fainted body lies rolled onto its side, about its forward axis.
SIDE = 1.25


def faint(count, side=SIDE):
    """It gives way (#1074): it wobbles one way, catches itself, then tips over the other way onto
    its side (`side` radians), the tail flopping after it, bounces once and keeps sinking into its
    hold, the head drooping and the tail curling in, rather than freezing there. The ground lifts
    it wherever it would sink in (clips.animate)."""
    wobble = _tail(count, {"root": (0.0, 0.0, 0.12), HEAD: (0.1, 0.0, 0.1)}, [(0.0, 0.0, 0.15)])
    caught = _tail(count, {"root": (0.0, 0.0, -0.05), HEAD: (-0.04, 0.0, -0.05)}, [(0.0, 0.0, -0.08)])
    tipping = _tail(count, {"root": (0.05, 0.0, -side * 0.5), HEAD: (0.1, 0.0, 0.0)}, [(0.0, 0.0, 0.2)])
    lying = _tail(count, {"root": (0.06, 0.0, -side), BODY: (0.0, 0.0, 0.1), HEAD: (0.15, 0.0, 0.15)},
                  [(-0.1, 0.0, 0.25), (0.0, 0.0, 0.2)])
    bounce = dict(lying, root=(0.05, 0.0, -side * 0.9))
    still = _tail(count, dict(lying, root=(0.07, 0.0, -side * 1.03), **{HEAD: (0.18, 0.0, 0.18)}),
                  [(-0.12, 0.0, 0.3), (0.0, 0.0, 0.26)])
    return clips.Clip([(1, {}), (6, wobble), (11, caught), (20, tipping), (30, lying), (33, bounce, "quart"),
                       (37, lying), (50, still)], planted=False)


# How many frames its wind-up (ChannelStart) takes.
CHANNEL_START = 24


def _held(count, t):
    """The long attack's held pose at `t` (0..1) of its loop: reared back, head high and puffed,
    the head throbbing up twice and swaying once to each side. Every wave leaves the pose at
    t=0 with no speed, and the tail is held up stiff (a quivering tail would still trail behind
    at the loop's start, a step from the wind-up's still end: motion.follow), so the wind-up's
    end, the loop's seam and the release's start meet without a jolt (clips._braced's way)."""
    throb = 0.5 - 0.5 * math.cos(4.0 * math.pi * t)
    sway = math.sin(2.0 * math.pi * t) ** 3
    # Only the head moves: the body turning would swing the stiff tail, which would trail behind.
    pose = {"root_loc": (0.0, 0.0, -0.12), "root": (-0.12, 0.0, 0.0), BODY: (-0.06, 0.0, 0.0),
            HEAD: (-0.12 - 0.04 * throb, 0.0, 0.08 * sway)}
    return _tail(count, pose, [(0.18, 0.0, 0.0), (0.1, 0.0, 0.0)])


def channel(count, frames=60):
    """A long attack, held for as long as it lasts (#1158), as three clips the game plays in turn
    (name: Clip): ChannelStart rears up, snaps forward and settles into the held stance; Channel
    holds it, a loop of `frames`, the head throbbing; ChannelEnd lets it go with a
    snap forward and settles. The start ends and the end starts on the loop's first pose."""
    held = _held(count, 0.0)
    rear = _tail(count, {"root_loc": (0.0, 0.0, -0.2), "root": (-0.18, 0.0, 0.0), HEAD: (-0.2, 0.0, 0.0)},
                 [(0.3, 0.0, 0.0), (0.2, 0.0, 0.0)])
    reared = dict(rear, root_loc=(0.0, 0.0, -0.23), root=(-0.2, 0.0, 0.0))
    snap = dict(held, root_loc=(0.0, 0.03, 0.05), root=(-0.06, 0.0, 0.0))
    start = clips.Clip([(1, {}), (9, rear), (11, reared), (17, snap, "quart"), (CHANNEL_START, held)], planted=False)
    loop = clips.Clip([(step + 1, _held(count, step / frames)) for step in range(frames + 1)], loop=True,
                      planted=False)
    burst = _tail(count, {"root_loc": (0.0, 0.05, 0.25), "root": (0.08, 0.0, 0.0), HEAD: (0.12, 0.0, 0.0)},
                  [(-0.2, 0.0, 0.0), (-0.1, 0.0, 0.0)])
    past = _tail(count, {"root_loc": (0.0, 0.0, -0.03), "root": (-0.02, 0.0, 0.0)}, [(0.05, 0.0, 0.0)])
    end = clips.Clip([(1, held), (6, burst, "quart"), (16, past), (26, {})], planted=False)
    return {"ChannelStart": start, "Channel": loop, "ChannelEnd": end}


def feed(count, frames=90, nibbles=3, pitch=0.18, head=0.12):
    """Feeding at its grass or water (#1281): it tips forward `pitch` radians onto its chin, the
    head bent down `head` more, and nibbles `nibbles` times a loop of `frames` frames, each a quick
    dip of the head and a tug back up; it breathes and its tail sways slowly. Every wave a whole
    number of times a loop, so the seam is exact."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        bite = 0.5 + 0.5 * clips._flat_wave(nibbles * lap - math.pi / 2.0)
        tug = 0.5 + 0.5 * math.sin(nibbles * lap - math.pi)
        breath = 0.5 - 0.5 * math.cos(lap)
        pose = {"root_loc": (0.0, 0.01 * breath, 0.0), "root": (pitch, 0.0, 0.0),
                BODY: (0.02 * breath, 0.0, 0.03 * math.sin(lap)),
                HEAD: (head + 0.08 * bite - 0.05 * tug, 0.0, 0.06 * math.sin(lap))}
        _wave(pose, count, lap, 0.08, 0.8, lift=-0.05)
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)


def sleep(count, frames=240, breaths=2, curl=0.22):
    """Asleep (#1229): it lies low, the head resting a little down and turned, the tail curled
    round to one side (`curl` radians a bone), breathing slowly, `breaths` breaths a loop of
    `frames` frames; the lids stay shut (eyes.Lids)."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        breath = 0.5 - 0.5 * math.cos(breaths * lap)
        pose = {"root_loc": (0.0, 0.01 * breath, 0.0), "root": (0.04, 0.0, 0.0),
                BODY: (-0.02 * breath, 0.0, 0.06), HEAD: (0.06 + 0.02 * breath, 0.0, 0.12)}
        _tail(count, pose, [(-0.04, 0.0, curl + 0.03 * math.sin(lap)), (0.0, 0.0, curl)])
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)
