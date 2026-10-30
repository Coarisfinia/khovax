"""A flutterer (#1732): a round body standing on two thin, dangling legs, with two stiff loops on
its top that beat like wings. It stands on its feet at rest and flies to move, a little off the
ground, its legs trailing below it: no paw is ever planted, so quadruped's and hexapod's legs
don't apply. The Tikazzelu, a ball of ribbons, is the first.

- `armature`: root, `body` (the body's lower half, from where the legs hang to its middle,
  pointing up), `crown` (its upper half, from its middle to its top), a wing chain `wing_01`,
  `wing_02`, ... on each side of the crown and a leg chain `leg_01`, `leg_02`, ... under the body,
  `.L`/`.R`. No bone is named a paw or a foot: the feet never stand while the game moves it, so
  the motion check has no sliding to measure. Every bone is rolled so its local Z is the forward
  axis (world -Y) turned square to it: turning about X pitches the body forward, swings a leg back
  and sweeps a wing forward; about Z a wing beats, up for a positive turn on the left and a
  negative one on the right (`_wing`).
- `bind`: each separate piece of the skin (welded by position) goes to the chain nearest its
  middle, the body or a wing or a leg, and each vertex of it is weighted along its chain by where
  it lies, blended between the bones' anchors, the chain's first joint belonging to the bone it
  hangs from, so a wing or leg bends out of the body smoothly. Plain Python floats, so every
  machine gives the same weights.
- The clips, every creature clip (lib/clip_set.py), posed on every bone and unplanted (`Clip`'s
  `planted=False`): `idle` (standing, breathing, its crown swirling and its wings twitching),
  `fly` (Walk and Run: hovering on beating wings, leaning into the flight, legs trailing),
  `attack` (it draws back high and darts at its target), `hit`, `faint` (its legs give way and it
  tips onto its side), `channel`, `feed` (it bows to the ground and pecks) and `sleep` (it sinks
  onto its folded legs, wings folded down). Every wave runs a whole number of times a loop.

Blender is Z-up and the body faces -Y. A pose's "root" turns the whole body about its feet: about
X it pitches (positive: forward), about Z, the root's forward axis, it rolls onto its side; its
"root_loc" is (sideways, up, forward)."""

import math

import bpy
from mathutils import Vector

from . import clips, motion, scene

BODY, CROWN = "body", "crown"
SIDES = ("L", "R")
# How long the root bone is (metres): it deforms nothing.
ROOT_LENGTH = 0.3
# Where a chain's first bone takes over from the bone it hangs from, as a share of its length:
# the rest of the way to its middle, the two blend.
TAKE_OVER = 0.3


def wing(count, side):
    """A wing's bones on `side`, from its root to its tip."""
    return ["wing_%02d.%s" % (index + 1, side) for index in range(count)]


def leg(count, side):
    """A leg's bones on `side`, from its hip to its toe."""
    return ["leg_%02d.%s" % (index + 1, side) for index in range(count)]


class Body:
    """Where a flutterer's joints are, in metres, its left side (+X; the right mirrors it): `hips`
    (the bottom of the body bone, between where the legs hang), `middle` (the body's middle, where
    the crown starts), `top`, `wing` (the left wing's joints from its root on the crown to its tip)
    and `leg` (the left leg's joints from its hip to its toe)."""

    def __init__(self, hips, middle, top, wing, leg):
        self.hips, self.middle, self.top = hips, middle, top
        self.wing, self.leg = list(wing), list(leg)


def _mirror(point):
    return (-point[0], point[1], point[2])


def scaled(body, scale):
    """`body` with every joint `scale` times as far from the origin."""
    def at(point):
        return tuple(scale * value for value in point)

    return Body(at(body.hips), at(body.middle), at(body.top), [at(point) for point in body.wing],
                [at(point) for point in body.leg])


def chains(body):
    """{chain: (parent bone, [(bone, head, tail)])} for the body and each wing and leg."""
    out = {"body": (None, [(BODY, body.hips, body.middle), (CROWN, body.middle, body.top)])}
    for side in SIDES:
        flip = (lambda point: point) if side == "L" else _mirror
        for name, parent, points, bones in (("wing", CROWN, body.wing, wing), ("leg", BODY, body.leg, leg)):
            joints = [flip(point) for point in points]
            out["%s.%s" % (name, side)] = (parent, [(bone, head, tail) for bone, head, tail in zip(
                bones(len(joints) - 1, side), joints, joints[1:])])
    return out


def armature(name, body):
    """The armature of `body`, each bone's local Z turned toward the front (world -Y)."""
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(rig)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    root = data.edit_bones.new("root")
    root.head, root.tail = Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, ROOT_LENGTH))
    root.use_deform = False
    for _chain, (parent, bones) in chains(body).items():
        for bone_name, head, tail in bones:
            bone = data.edit_bones.new(bone_name)
            bone.head, bone.tail = Vector(head), Vector(tail)
            bone.parent = data.edit_bones[parent or "root"]
            parent = bone_name
            direction = (bone.tail - bone.head).normalized()
            bone.align_roll(Vector((1.0, 0.0, 0.0)).cross(direction))
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _smooth(share):
    share = max(0.0, min(1.0, share))
    return share * share * (3.0 - 2.0 * share)


def _along(point, joints):
    """How far along the polyline `joints` the point nearest `point` lies (metres from its start;
    less than nothing before it), and how far `point` is from it."""
    best, reach = None, 0.0
    for start, end in zip(joints, joints[1:]):
        length = (end - start).length
        t = (point - start).dot(end - start) / (length * length)
        # The first segment runs on backwards, so a vertex above a leg's hip reads as before it.
        clamped = max(0.0 if best is not None or t > 0.0 else t, min(1.0, t))
        distance = (point - (start + (end - start) * clamped)).length
        if best is None or distance < best[1]:
            best = (reach + clamped * length, distance)
        reach += length
    return best


def _anchors(parent, bones):
    """[(metres along the chain, bone)]: where each bone holds a vertex wholly, the parent at the
    chain's start."""
    out = [] if parent is None else [(0.0, parent)]
    reach = 0.0
    for index, (bone, head, tail) in enumerate(bones):
        length = (Vector(tail) - Vector(head)).length
        share = TAKE_OVER if index == 0 and parent is not None else 0.5
        out.append((reach + share * length, bone))
        reach += length
    return out


def pieces(mesh):
    """Each vertex's piece: a number per vertex index, the vertices joined by an edge, or lying on
    the same spot (the export's seam splits), sharing one."""
    parent = list(range(len(mesh.vertices)))

    def top(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def join(first, second):
        first, second = top(first), top(second)
        if first != second:
            parent[max(first, second)] = min(first, second)

    spots = {}
    for vertex in mesh.vertices:
        join(vertex.index, spots.setdefault(tuple(vertex.co), vertex.index))
    for edge in mesh.edges:
        join(*edge.vertices)
    numbers = {}
    return [numbers.setdefault(top(index), len(numbers)) for index in range(len(mesh.vertices))]


def bind(skin, rig, body):
    """Weights `skin` to `rig` (built from `body`, at the skin's size) piece by piece along the
    chain nearest each piece's middle."""
    scene.select_only(skin)
    skin.parent = rig
    skin.modifiers.new("Armature", "ARMATURE").object = rig
    to_rig = rig.matrix_world.inverted() @ skin.matrix_world
    found = chains(body)
    polylines = {name: [Vector(bones[0][1])] + [Vector(tail) for _bone, _head, tail in bones]
                 for name, (_parent, bones) in found.items()}
    points = [to_rig @ vertex.co for vertex in skin.data.vertices]
    owner = pieces(skin.data)
    middles = {}
    for index, piece in enumerate(owner):
        total, count = middles.get(piece, (Vector(), 0))
        middles[piece] = (total + points[index], count + 1)
    home = {}
    for piece, (total, count) in sorted(middles.items()):
        middle = total / count
        home[piece] = min(sorted(polylines), key=lambda name: _along(middle, polylines[name])[1])
    groups = {}
    for index, point in enumerate(points):
        name = home[owner[index]]
        parent, bones = found[name]
        anchors = _anchors(parent, bones)
        at = _along(point, polylines[name])[0]
        weights = {}
        if at <= anchors[0][0]:
            weights[anchors[0][1]] = 1.0
        elif at >= anchors[-1][0]:
            weights[anchors[-1][1]] = 1.0
        else:
            for (start, first), (end, second) in zip(anchors, anchors[1:]):
                if at <= end:
                    share = _smooth((at - start) / (end - start))
                    weights = {first: 1.0 - share, second: share}
                    break
        for bone, weight in weights.items():
            if weight > 0.0:
                if bone not in groups:
                    groups[bone] = skin.vertex_groups.new(name=bone)
                groups[bone].add([index], weight, "REPLACE")
    return {piece: home[piece] for piece in home}


def follow(wings, legs):
    """motion.follow's springs: the crown trails the body, each wing bone its root, looser toward
    the tip, and the legs dangle, swung by the root's movement (their `shift`) as much as by the
    body's turn."""
    out = {CROWN: (1.8, 0.5, 0.0, 0.1)}
    for side in SIDES:
        for index, name in enumerate(wing(wings, side)):
            out[name] = (2.6 + 0.4 * index, 0.45, 0.0, 0.1)
        for index, name in enumerate(leg(legs, side)):
            out[name] = (1.7 + 0.3 * index, 0.42, 0.0, 0.35 - 0.08 * index)
    return out


class Pose:
    """One pose being built: the body's turns, both wings' and legs' by side, and the root."""

    def __init__(self, wings, legs):
        self.wings, self.legs = wings, legs
        self.pose = {}

    def root(self, loc=(0.0, 0.0, 0.0), turn=(0.0, 0.0, 0.0)):
        self.pose["root_loc"] = tuple(loc)
        self.pose["root"] = tuple(turn)
        return self

    def body(self, turn=(0.0, 0.0, 0.0), crown=(0.0, 0.0, 0.0)):
        self.pose[BODY] = tuple(turn)
        self.pose[CROWN] = tuple(crown)
        return self

    def wing(self, beat, sweep=0.0, tip=None, offset=0.0):
        """Both wings: beaten up `beat` radians (the left a positive turn about Z, the right a
        negative one) and swept forward `sweep`; the tip bones beat `tip` more (half `beat` unless
        given). `offset` beats the right wing that much less than the left (a twitch of one)."""
        tip = 0.5 * beat if tip is None else tip
        for side, sign in (("L", 1.0), ("R", -1.0)):
            lift = beat - (offset if side == "R" else 0.0)
            for index, name in enumerate(wing(self.wings, side)):
                self.pose[name] = (sweep if index == 0 else 0.3 * sweep, 0.0,
                                   sign * (lift if index == 0 else tip))
        return self

    def leg(self, swing, splay=0.0, bends=(), stagger=0.0):
        """Both legs: swung back `swing` radians at the hip (the right `stagger` more, the left that
        much less) and spread `splay` out; `bends` each next bone's own swing back."""
        for side, sign in (("L", 1.0), ("R", -1.0)):
            for index, name in enumerate(leg(self.legs, side)):
                if index == 0:
                    own = swing + (stagger if side == "R" else -stagger)
                    self.pose[name] = (own, 0.0, -sign * splay)
                else:
                    self.pose[name] = (bends[index - 1] if index - 1 < len(bends) else 0.0, 0.0, 0.0)
        return self

    def standing(self):
        """Turns the legs' hips back by the body's and root's pitch and roll, so they hang straight
        down under a turned body and the feet stay where they stand (small turns)."""
        pitch = self.pose.get("root", (0.0, 0.0, 0.0))[0] + self.pose.get(BODY, (0.0, 0.0, 0.0))[0]
        roll = self.pose.get("root", (0.0, 0.0, 0.0))[2] + self.pose.get(BODY, (0.0, 0.0, 0.0))[2]
        for side in SIDES:
            name = leg(self.legs, side)[0]
            x, y, z = self.pose.get(name, (0.0, 0.0, 0.0))
            # A leg's Z is the body's backward axis (its own forward one turned down), so its
            # roll undoes the body's with the same sign.
            self.pose[name] = (x - pitch, y, z + roll)
        return self


def idle(wings, legs, breath=90, breaths=2):
    """Standing, alive: the body swells and settles `breaths` times a loop of `breath` frames,
    rocking a little from side to side, the crown's ribbons swirling slowly against it; the wings
    beat lazily with each breath and one twitches now and then, and the legs stay straight under
    it."""
    frames = breath * breaths
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        chest = 0.5 - 0.5 * math.cos(breaths * lap)
        twitch = max(0.0, math.sin(3.0 * lap + 0.4)) ** 6
        pose = (Pose(wings, legs)
                .body((0.03 * chest - 0.015, 0.05 * math.sin(lap + 0.5), 0.03 * math.sin(lap)),
                      (0.02 * math.sin(breaths * lap + 1.0), 0.10 * math.sin(lap + 1.2), 0.02 * math.sin(lap + 2.0)))
                .wing(0.08 * chest + 0.12 * twitch, 0.04 * math.sin(lap + 0.7), offset=0.12 * twitch)
                .leg(0.0)
                .standing())
        poses.append((step + 1, pose.pose))
    return clips.Clip(poses, loop=True, planted=False)


def fly(wings, legs, frames, hover, beat, pitch, beats=2, trail=0.35):
    """Flying on: hovering `hover` metres up, the wings beating `beat` radians either side of
    raised, `beats` times a loop of `frames` frames, the body bobbing up on each downstroke and
    leaning `pitch` radians into the flight, the crown's ribbons swirling, the legs trailing back
    `trail` radians and paddling against each other. Posed on every frame; the game moves it
    along."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        stroke = math.sin(beats * lap)
        pose = (Pose(wings, legs)
                .root((0.0, hover + 0.25 * hover * math.sin(beats * lap - 1.2), 0.0),
                      (pitch, 0.0, 0.04 * math.sin(lap)))
                .body((0.04 * math.sin(beats * lap - 0.5), 0.04 * math.sin(lap), 0.0),
                      (0.05 * math.sin(beats * lap - 1.0), 0.14 * math.sin(lap + 0.6), 0.03 * math.sin(lap)))
                .wing(0.25 + beat * stroke, -0.2 + 0.15 * math.cos(beats * lap), tip=0.5 * beat * math.sin(beats * lap - 0.8))
                .leg(trail, 0.05, bends=(0.25 + 0.1 * math.sin(lap - 0.6), 0.3), stagger=0.12 * math.sin(lap)))
        poses.append((step + 1, pose.pose))
    return clips.Clip(poses, loop=True, planted=False)


def attack(wings, legs, reach=0.5):
    """Anticipation, action, overshoot and settle (#1074): it rises and draws back, wings high,
    still drawing back as it holds; darts `reach` metres at its target, leaning into it with its
    wings swept back and its legs flung behind, and strikes with its body; pulls back, sways past
    where it stood and settles onto its feet."""
    def pose():
        return Pose(wings, legs)

    drawn = pose().root((0.0, 0.10, -0.12), (-0.25, 0.0, 0.0)).body((-0.05, 0.0, 0.0), (-0.08, 0.0, 0.0)) \
        .wing(0.65, 0.25).leg(-0.25, 0.08, bends=(0.2,))
    coiled = pose().root((0.0, 0.12, -0.15), (-0.30, 0.0, 0.0)).body((-0.06, 0.0, 0.0), (-0.10, 0.0, 0.0)) \
        .wing(0.75, 0.3).leg(-0.3, 0.1, bends=(0.25,))
    lunge = pose().root((0.0, 0.10, 0.8 * reach), (0.45, 0.0, 0.0)).body((0.08, 0.0, 0.0), (0.10, 0.0, 0.0)) \
        .wing(-0.35, -0.6).leg(0.8, 0.05, bends=(0.3, 0.2))
    strike = pose().root((0.0, 0.08, reach), (0.55, 0.0, 0.0)).body((0.12, 0.0, 0.0), (0.16, 0.0, 0.0)) \
        .wing(-0.45, -0.7).leg(0.9, 0.05, bends=(0.35, 0.2))
    back = pose().root((0.0, 0.04, 0.2 * reach), (0.08, 0.0, 0.0)).body((0.0, 0.0, 0.0), (0.03, 0.0, 0.0)) \
        .wing(0.3, 0.0).leg(0.2)
    past = pose().root((0.0, 0.0, -0.03), (-0.04, 0.0, 0.0)).wing(0.1, 0.05).leg(0.0).standing()
    return clips.Clip([(1, {}), (8, drawn.pose), (11, coiled.pose), (18, lunge.pose, "back"),
                       (21, strike.pose, "quart"), (28, back.pose, "quart"), (33, past.pose), (40, {})],
                      planted=False)


def hit(wings, legs):
    """Recoil from a blow (#1074): it's knocked back and up, the body tipped back, the wings flung
    up and the legs forward, a shiver running through it; then it rebounds past where it stood and
    settles."""
    recoil = Pose(wings, legs).root((0.0, 0.06, -0.18), (-0.3, 0.0, 0.08)).body((-0.06, 0.0, 0.08), (-0.1, 0.12, 0.0)) \
        .wing(0.7, 0.3, offset=0.15).leg(-0.35, 0.12, bends=(0.2,))
    reeling = Pose(wings, legs).root((0.0, 0.07, -0.22), (-0.34, 0.0, 0.09)).body((-0.07, 0.0, 0.09), (-0.12, 0.14, 0.0)) \
        .wing(0.75, 0.3, offset=0.15).leg(-0.4, 0.12, bends=(0.22,))
    rebound = Pose(wings, legs).root((0.0, 0.0, 0.04), (0.06, 0.0, -0.03)).body((0.03, 0.0, -0.02), (0.04, -0.05, 0.0)) \
        .wing(-0.1, -0.05).leg(0.0).standing()
    shiver = motion.Shiver([BODY, CROWN], 4, 18, math.radians(2.5))
    return clips.Clip([(1, {}), (4, recoil.pose, "expo"), (8, reeling.pose), (17, rebound.pose), (27, {})],
                      planted=False, shiver=shiver)


# How far (radians) a fainted body lies rolled onto its side, about its forward axis.
SIDE = 1.3


def faint(wings, legs, side=SIDE):
    """It gives way (#1074): it wobbles one way, catches itself with a beat of its wings, then its
    legs buckle and it tips over the other way onto its side (`side` radians), wings flopping, bounces
    once and keeps sinking into its hold, the wings drooping and the legs curling, rather than
    freezing there. The ground lifts it wherever it would sink in (clips.animate)."""
    wobble = Pose(wings, legs).root(turn=(0.0, 0.0, 0.14)).body((0.05, 0.0, 0.06), (0.06, 0.0, 0.05)) \
        .wing(0.05, 0.0, offset=-0.2).leg(0.0).standing()
    caught = Pose(wings, legs).root(turn=(0.0, 0.0, -0.05)).body((0.02, 0.0, -0.03)).wing(0.45, 0.1).leg(0.0).standing()
    buckle = Pose(wings, legs).root((0.0, -0.06, 0.0), (0.05, 0.0, -side * 0.5)).body((0.1, 0.0, 0.0), (0.1, 0.0, 0.0)) \
        .wing(-0.2, -0.1).leg(-0.5, 0.15, bends=(0.9, -0.3))
    lying = Pose(wings, legs).root((0.0, -0.08, 0.0), (0.06, 0.0, -side)).body((0.08, 0.0, 0.05), (0.12, 0.1, 0.0)) \
        .wing(-0.45, -0.2, offset=-0.3).leg(-0.6, 0.25, bends=(1.0, -0.4))
    bounce = Pose(wings, legs).root((0.0, -0.06, 0.0), (0.05, 0.0, -side * 0.9)).body((0.08, 0.0, 0.05), (0.1, 0.08, 0.0)) \
        .wing(-0.3, -0.15, offset=-0.2).leg(-0.55, 0.22, bends=(0.95, -0.35))
    still = Pose(wings, legs).root((0.0, -0.09, 0.0), (0.07, 0.0, -side * 1.03)).body((0.1, 0.0, 0.06), (0.15, 0.12, 0.0)) \
        .wing(-0.55, -0.25, offset=-0.35).leg(-0.7, 0.28, bends=(1.15, -0.45))
    return clips.Clip([(1, {}), (6, wobble.pose), (11, caught.pose), (20, buckle.pose), (30, lying.pose),
                       (33, bounce.pose, "quart"), (37, lying.pose), (52, still.pose)], planted=False)


# How many frames its wind-up (ChannelStart) takes.
CHANNEL_START = 24


def _held(wings, legs, t, hover):
    """The long attack's held pose at `t` (0..1) of its loop: hovering `hover` metres up, wings
    spread high and quivering in two slow beats, the crown's ribbons turning once to each side.
    Every wave leaves the pose at t=0 with no speed, so the wind-up's end, the loop's seam and
    the release's start meet without a jolt (clips._braced's way)."""
    rise = 0.5 - 0.5 * math.cos(4.0 * math.pi * t)
    turn = math.sin(2.0 * math.pi * t) ** 3
    return (Pose(wings, legs)
            .root((0.0, hover + 0.03 * rise, 0.0), (-0.1, 0.0, 0.0))
            .body((-0.04, 0.0, 0.0), (-0.06 - 0.03 * rise, 0.18 * turn, 0.0))
            .wing(0.7 + 0.12 * rise, 0.15, tip=0.25)
            .leg(0.1, 0.12, bends=(0.25, 0.2))).pose


def channel(wings, legs, hover=0.14, frames=60):
    """A long attack, held for as long as it lasts (#1158), as three clips the game plays in turn
    (name: Clip): ChannelStart crouches, springs up into a hover and spreads its wings; Channel
    holds it, a loop of `frames`; ChannelEnd lets it go with a dart forward and lands. The start
    ends and the end starts on the loop's first pose."""
    held = _held(wings, legs, 0.0, hover)
    crouch = Pose(wings, legs).root((0.0, -0.03, 0.0), (0.1, 0.0, 0.0)).body((0.05, 0.0, 0.0), (0.06, 0.0, 0.0)) \
        .wing(-0.15, -0.1).leg(0.0, 0.05, bends=(0.3,)).standing()
    spring_ = Pose(wings, legs).root((0.0, hover + 0.05, 0.0), (-0.15, 0.0, 0.0)).body((-0.05, 0.0, 0.0), (-0.08, 0.0, 0.0)) \
        .wing(0.9, 0.2, tip=0.3).leg(0.15, 0.12, bends=(0.3, 0.2))
    start = clips.Clip([(1, {}), (8, crouch.pose), (16, spring_.pose, "quart"), (CHANNEL_START, held)], planted=False)
    loop = clips.Clip([(step + 1, _held(wings, legs, step / frames, hover)) for step in range(frames + 1)], loop=True,
                      planted=False)
    burst = Pose(wings, legs).root((0.0, 0.08, 0.25), (0.3, 0.0, 0.0)).body((0.06, 0.0, 0.0), (0.1, 0.0, 0.0)) \
        .wing(-0.3, -0.5).leg(0.6, 0.05, bends=(0.3, 0.2))
    past = Pose(wings, legs).root((0.0, 0.0, 0.04), (-0.04, 0.0, 0.0)).wing(0.15, 0.0).leg(0.0).standing()
    end = clips.Clip([(1, held), (7, burst.pose, "quart"), (17, past.pose), (28, {})], planted=False)
    return {"ChannelStart": start, "Channel": loop, "ChannelEnd": end}


def feed(wings, legs, frames=90, pecks=3, bow=0.35):
    """Feeding at its grass or water (#1281): it bows `bow` radians over its feet and pecks
    `pecks` times a loop of `frames` frames, each a quick dip of the crown and a tug back up, its
    wings lifting a little with each tug; the legs stay straight under it. Every wave a whole
    number of times a loop, so the seam is exact."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        bite = 0.5 + 0.5 * clips._flat_wave(pecks * lap - math.pi / 2.0)
        tug = 0.5 + 0.5 * math.sin(pecks * lap - math.pi)
        breath = 0.5 - 0.5 * math.cos(lap)
        pose = (Pose(wings, legs)
                .root(turn=(bow, 0.0, 0.0))
                .body((0.05 + 0.08 * bite - 0.03 * tug, 0.0, 0.02 * math.sin(lap)),
                      (0.1 + 0.1 * bite, 0.05 * math.sin(lap), 0.0))
                .wing(0.05 + 0.12 * tug + 0.03 * breath, -0.1)
                .leg(0.0)
                .standing())
        poses.append((step + 1, pose.pose))
    return clips.Clip(poses, loop=True, planted=False)


def sleep(wings, legs, frames=240, breaths=2, sink=0.16):
    """Asleep (#1229): it sinks `sink` metres onto its folded legs, the crown tipped a little to one
    side and its wings folded down over its sides, breathing slowly, `breaths` breaths a loop of
    `frames` frames, the ribbons drifting with each breath."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * (step % frames) / frames
        breath = 0.5 - 0.5 * math.cos(breaths * lap)
        pose = (Pose(wings, legs)
                .root((0.0, -sink + 0.008 * breath, 0.0), (0.04, 0.0, 0.0))
                .body((-0.02 * breath, 0.0, 0.04), (0.05 + 0.02 * breath, 0.06 * math.sin(lap), 0.08))
                .wing(-0.5 + 0.04 * breath, -0.3, tip=-0.2)
                .leg(-1.2, 0.2, bends=(2.2, -0.6)))
        poses.append((step + 1, pose.pose))
    return clips.Clip(poses, loop=True, planted=False)
