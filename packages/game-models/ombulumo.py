"""The Ombulumo (#1271): a round, soggy creature of still water that sits half-sunk in the shallows
and booms at dusk. A squat, toad-like dome on short splayed legs with webbed feet, a broad flat
head with a wide mouth, round eyes bulging on top, a pale throat sac that swells as it booms, two
leaf fronds behind its eyes, moss pads on its back and soft glowing spots. Only its parameters and
its own parts live here; the building blocks are the shared library in packages/game-models/lib/
(model skill).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/ombulumo.py -- packages/game/assets/ombulumo/ombulumo.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes.

Blender is Z-up and it faces -Y (the game's +Z). Sizes are in metres, shrunk by SCALE at the end
to sit on one hex tile.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import attachments, body, clips, eyes, legs, metrics, muzzle, parts, pulse, quadruped, scene, surface, symmetry, weights  # noqa: E402
from lib.materials import palette  # noqa: E402

FPS = 30
# Sturdier than the mana wolf, it stands a little larger on its tile.
SCALE = 0.95
# The body's budget before its parts, as the mana wolf's: seen full-screen on its codex page.
BODY_TRIANGLES = 9000

# A deep teal green, so it stands out from the grass; a pale throat sac; moss pads and fronds in
# a brighter green; and soft lime glows.
COLORS = {
    "skin": ((0.06, 0.20, 0.17, 1.0), 0.0),
    "light": ((0.80, 0.72, 0.48, 1.0), 0.0),
    "moss": ((0.30, 0.48, 0.08, 1.0), 0.0),
    "glow": ((0.62, 1.0, 0.18, 1.0), 1.0),
    "dark": ((0.02, 0.03, 0.03, 1.0), 0.0),
}

TOAD = quadruped.Proportions(
    # A stub of a tail, mostly inside the round rump.
    tail=[(0.0, 0.76, 0.34), (0.0, 0.71, 0.37), (0.0, 0.66, 0.40), (0.0, 0.61, 0.43)],
    hips=(0.0, 0.40, 0.52),
    waist=(0.0, 0.14, 0.56),
    chest=(0.0, -0.16, 0.58),
    head_base=(0.0, -0.36, 0.62),
    nose=(0.0, -0.88, 0.58),
    # Every quadruped rig has a jaw; this one's mouth is drawn on (MOUTH), so it moves nothing.
    jaw=((0.0, -0.40, 0.52), (0.0, -0.84, 0.47)),
    # The leaf fronds take the ears' bones, far enough behind the eyes that, flattened back or
    # twitching, they never cross them (check_brows.py).
    ear=((0.25, -0.27, 0.80), (0.40, -0.09, 0.92)),
    scapula=(0.38, -0.10, 0.58),
    front_leg=[(0.40, -0.34, 0.40), (0.42, -0.20, 0.22), (0.43, -0.24, 0.08), (0.43, -0.32, 0.04)],
    hind_leg=[
        (0.44, 0.36, 0.42),
        (0.46, 0.12, 0.30),
        (0.47, 0.42, 0.18),
        (0.47, 0.36, 0.06),
        (0.47, 0.20, 0.05),
    ],
)
# Its proportions as first built (#1271): a change that drifts from them fails the build
# (lib/metrics.py), so a derpy edit shows as numbers. A toad's: a head as long as the body is
# deep and wider than it is long, short legs, eyes far apart on top, a short, deep, blunt muzzle.
REFERENCE = {
    "head/body": 1.307,
    "head height/length": 0.941,
    "head width/length": 1.203,
    "leg/body": 0.719,
    # The leaf fronds behind the eyes, on the ears' bones.
    "ear/head": 0.410,
    # The stub of a tail and the round rump it moves.
    "tail/body": 0.799,
    "eye spacing/head width": 0.625,
    # The eyes mirror each other: level, side by side, equally far out.
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
    "muzzle/head": 0.609,
    "muzzle depth/length": 1.072,
    "muzzle width/head width": 0.725,
    "nose width/muzzle width": 0.409,
}

# A wide, blunt muzzle across the whole front of the head. Its mouth is a line drawn round the
# head's front (MOUTH), not a jaw that opens: a cut as wide as a toad's would leave flaps of skin.
SNOUT = muzzle.Snout(stop=(-0.60, 0.74), tip=(-0.86, 0.60), radius=0.20, joint=TOAD.jaw[0][1:], taper=0.85,
                     stop_depth=0.02, lip=0.03, jaw_depth=0.6, jaw_width=1.0, chin=0.85, corner=0.0)

TAIL_ROOT = (0.0, 0.55, 0.44)

# The mouth's line, cheek to cheek round the front of the head, a little above the chin.
MOUTH = [(0.40 * math.sin(1.25 * share), -0.42 - 0.46 * math.cos(1.25 * share), 0.50)
         for share in (index / 8 - 1.0 for index in range(17))]

# The eyes' turrets on top of the head (the left one; the right mirrors it): the skin there moves
# with the head alone, so it never slides across the eye set into it (check_brows.py).
TURRET, TURRET_RADIUS = (0.24, -0.52, 0.80), 0.12

# How high its belly sits off the ground: the faint and the sleep sink it this far.
BELLY_HEIGHT = 0.16

# The game's speeds at the model's size (metres a second): a wild monster glides a tile (sqrt(3)
# apart) in 0.8 s, a companion follows at a tile every 0.3 s. Its legs are short, so a walk
# cycle covers two thirds of a tile, each foot only briefly down (a scurrying waddle), and each
# hop of its run takes as long as the game takes to carry it two tiles: a run is longer hops, not
# quicker legs. Like every clip it plays in place (the game moves the model), so its hops carry
# no stride of their own: its feet skim the ground rather than stand on it (hop).
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * 2 / 3, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * 2, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE

# The throat sac booms (#1271): it swells from the back of the throat on its own bone
# (lib/pulse.py), twice in a resting loop, once as it leaps, and on every beat of its long attack,
# a boom every BOOM frames. A loop takes the beats either side of its seam.
THROAT, THROAT_BONE = (0.0, -0.46, 0.42), pulse.PREFIX + "throat"
BOOM, BOOM_SWELL, BOOM_RISE, BOOM_FALL = 20, 1.55, 6, 14
CHANNEL_FRAMES = 60


def mirror(point, sign):
    return (point[0] * sign, point[1], point[2])


def toad_body():
    """Soft forms: a round dome of a body, wider than it is long, a round rump, a broad flat head
    melting into it with no neck, eyes bulging on top, short splayed forelegs, thick folded hind
    legs with round haunches, wide webbed feet and a stub of a tail."""
    blob = body.Blob("Ombulumo")
    blob.ellipsoid((0.0, 0.08, 0.52), (0.62, 0.48, 0.36))
    blob.ellipsoid((0.0, 0.40, 0.46), (0.50, 0.26, 0.30))
    blob.ellipsoid((0.0, -0.22, 0.54), (0.52, 0.30, 0.28))
    # The head: broad and flat, its brow and upper lip from the snout, and a round chin.
    blob.ellipsoid((0.0, -0.50, 0.62), (0.47, 0.28, 0.18))
    SNOUT.upper(blob)
    blob.ellipsoid((0.0, -0.66, 0.47), (0.34, 0.22, 0.10))
    blob.tube([TAIL_ROOT, *reversed(TOAD.tail)], [0.10, 0.10, 0.085, 0.07, 0.055])
    for sign in (1, -1):
        # The eyes' turrets, on top of the head.
        blob.ball(mirror(TURRET, sign), TURRET_RADIUS)
        front = [mirror(p, sign) for p in TOAD.front_leg]
        blob.limb(front[:3], [0.12, 0.09, 0.06])
        hind = [mirror(p, sign) for p in TOAD.hind_leg]
        blob.limb(hind[1:4], [0.11, 0.08, 0.055])
        # The haunch: a round thigh folded against the flank.
        blob.ellipsoid(mirror((0.43, 0.26, 0.36), sign), (0.15, 0.24, 0.14), (0.15 * sign, -1.0, -0.25))
        # The webbed feet: a broad pad and round toes fanned out, three in front and four behind.
        for paw, toes, spread in ((front[2], 3, 0.55), (hind[3], 4, 0.7)):
            px, py, _pz = paw
            blob.ellipsoid((px, py - 0.06, 0.05), (0.08, 0.09, 0.04))
            for index in range(toes):
                turn = (index / (toes - 1) - 0.5) * spread * 2 * sign
                reach = 0.14
                toe = (px + math.sin(turn) * reach, py - 0.04 - math.cos(turn) * reach, 0.035)
                blob.capsule((px, py - 0.06, 0.04), toe, 0.024)
                blob.ball(toe, 0.034)
    return blob.mesh(BODY_TRIANGLES, symmetric=True)


def turrets(skin):
    """Hands the skin of the eyes' turrets wholly to the head (weights.bind's `reweigh`, after
    scene.apply_scale), so the eyes and their sockets move as one."""
    head = skin.vertex_groups["head"]
    centres = [Vector(mirror(TURRET, sign)) * SCALE for sign in (1, -1)]
    reach = TURRET_RADIUS * 1.6 * SCALE
    for vertex in skin.data.vertices:
        if min((vertex.co - centre).length for centre in centres) > reach:
            continue
        for group in [group.group for group in vertex.groups]:
            skin.vertex_groups[group].remove([vertex.index])
        head.add([vertex.index], 1.0, "REPLACE")


def leaf(name, base, toward, length, width, mat, bone=None):
    """A soft, flat leaf: a flattened ellipsoid from `base` toward `toward`, `length` long and
    `width` across, lying flat (its face up)."""
    direction = Vector(toward).normalized()
    center = Vector(base) + direction * length / 2
    return parts.part("uv_sphere", name, center, (width / 2, 0.012, length / 2),
                      parts.pointing(direction, up=(0.0, 0.0, 1.0)), mat, bone, segments=12, ring_count=8)


def head_parts(skin, mats):
    """The mouth, two nostrils, the leaf fronds and the round, bulging eyes."""
    # The mouth, a dark line from cheek to cheek round the front of the head, and two nostrils.
    made = [surface.vein(skin, "Mouth", MOUTH, 0.012, mats["dark"])]
    for sign in (1, -1):
        side = "L" if sign == 1 else "R"
        made.append(parts.part("uv_sphere", "Nostril." + side, (0.07 * sign, -0.855, 0.655), (0.018, 0.012, 0.012), mat=mats["dark"],
                               bone="head", segments=8, ring_count=5))
        base, tip = (mirror(p, sign) for p in TOAD.ear)
        out = tuple(t - b for t, b in zip(tip, base))
        for index, (share, length, width) in enumerate(((0.0, 0.30, 0.10), (0.15, 0.22, 0.08))):
            spot = tuple(b + o * share for b, o in zip(base, out))
            toward = (out[0] + 0.12 * index * sign, out[1] + 0.1 * index, out[2] + 0.08 * index)
            made.append(leaf("Frond.%d.%s" % (index, side), spot, toward, length, width, mats["moss"], "ear." + side))
    # The left eye, set into the skin, and its mirror image on the right. Its turret is its lid:
    # a brow ridge would float over a bulging eye.
    left = []
    for piece in eyes.eye(skin, "Eye.L", (0.27, -0.57, 0.90), (0.25, -1.0, 0.2), 0.09,
                          {"dark": mats["dark"], "glow": mats["glow"], "light": mats["light"], "skin": mats["skin"]},
                          "head", almond=0.95, pupil=(0.42, 0.34)):
        if piece.name.endswith(".brow"):
            bpy.data.objects.remove(piece, do_unlink=True)
        else:
            left.append(piece)
    made += left + [parts.mirrored(piece, piece.name.replace("Eye.L.", "Eye.R.")) for piece in left]
    return made


def throat(mats):
    """The pale throat sac under the chin, on a bone of its own so it swells as it booms."""
    return [parts.part("uv_sphere", "Throat", (0.0, -0.58, 0.36), (0.20, 0.16, 0.11), mat=mats["light"],
                       bone=THROAT_BONE, segments=16, ring_count=8)]


# The glowing spots along its back, on the left side (the right mirrors them): (y, how far out).
SPOTS = ((-0.18, 0.22), (0.02, 0.30), (0.22, 0.26), (0.40, 0.18), (-0.02, 0.12), (0.30, 0.08), (0.12, 0.40))
# The moss pads on its back: centre (x, y) and radius, the middle one, which sprouts, and the
# left one (the right mirrors it).
PADS = (((0.0, 0.10), 0.13), ((0.17, 0.30), 0.09))


def back(skin, mats):
    """Moss pads on its back, a sprout of two leaves from the middle one, and soft glowing spots."""
    made = []
    for name, ((x, y), radius) in zip(("Pad.0", "Pad.1.L"), PADS):
        found, location, normal, _index = skin.closest_point_on_mesh((x, y, 1.2))
        pad = parts.part("cylinder", name, location + normal * 0.005, (radius, radius, 0.012), parts.pointing(normal),
                         mats["moss"], vertices=16)
        made += [pad] if x == 0 else [pad, parts.mirrored(pad, "Pad.1.R")]
    sprout = surface.onto(skin, (0.0, 0.10, 1.2), 0.0)
    sprouting = leaf("Sprout.L", sprout, (0.6, 0.1, 1.0), 0.18, 0.07, mats["moss"])
    made += [sprouting, parts.mirrored(sprouting, "Sprout.R")]
    for index, (y, out) in enumerate(SPOTS):
        found, location, normal, _index = skin.closest_point_on_mesh((out, y, 1.2))
        size = 0.028 + 0.008 * (index % 3)
        spot = parts.part("uv_sphere", "Spot.%d.L" % index, location, (size, size, size * 0.4),
                          parts.pointing(normal), mats["glow"], segments=10, ring_count=5)
        made += [spot, parts.mirrored(spot, "Spot.%d.R" % index)]
    return made


def points(rig, pieces):
    """The attachment points (#1007): the eyes, and its one centre of attack, its wide mouth."""
    sides = {side: [piece for piece in pieces if piece.name.startswith("Eye.%s." % side)] for side in ("L", "R")}
    attachments.add(rig, {side: (eyes.spot(eye), "head", eyes.look(eye)) for side, eye in sides.items()},
                    [((0.0, -0.84, 0.55), "head")])


def leap():
    """Its attack (#1271): it crouches, still sinking as it gathers itself, leaps up and forward
    its throat swelling and every foot leaving the ground, lands on its target with all its soggy
    weight, squashing flat, wobbles back up and waddles back to where it stood."""
    crouch = {"root_loc": (0, -0.08, -0.04), "hips": (-0.10, 0, 0), "neck": (0.12, 0, 0), "head": (-0.08, 0, 0)}
    coiled = dict(crouch, root_loc=(0, -0.09, -0.05), hips=(-0.12, 0, 0))
    air = {"root_loc": (0, 0.18, 0.22), "hips": (0.10, 0, 0), "neck": (-0.12, 0, 0), "head": (-0.05, 0, 0),
           "tail_01": (0.3, 0, 0)}
    slam = {"root_loc": (0, -0.07, 0.40), "hips": (0.04, 0, 0), "neck": (0.14, 0, 0), "head": (0.10, 0, 0),
            "tail_01": (-0.2, 0, 0)}
    wobble = {"root_loc": (0, 0.02, 0.40), "hips": (-0.02, 0, 0), "neck": (-0.04, 0, 0), "head": (-0.03, 0, 0)}
    steps = []
    for side, late in (("L", 0), ("R", 1)):
        steps.append(legs.Step("front_paw." + side, 10 + late, 20 + late, (0.0, 0.0, 0.40), 0.18))
        steps.append(legs.Step("hind_paw." + side, 11 + late, 21 + late, (0.0, 0.0, 0.40), 0.16))
        steps.append(legs.Step("front_paw." + side, 27 + 2 * late, 33 + 2 * late, (0.0, 0.0, 0.18), 0.06))
        steps.append(legs.Step("hind_paw." + side, 29 + 2 * late, 35 + 2 * late, (0.0, 0.0, 0.18), 0.05))
        steps.append(legs.Step("front_paw." + side, 35 + 2 * late, 41 + 2 * late, (0.0, 0.0, 0.0), 0.06))
        steps.append(legs.Step("hind_paw." + side, 37 + 2 * late, 43 + 2 * late, (0.0, 0.0, 0.0), 0.05))
    return clips.Clip([(1, {}), (7, crouch), (11, coiled), (15, air),
                       (20, slam), (24, wobble, "back"), (34, {"root_loc": (0, 0, 0.2)}), (46, {})],
                      steps=steps)


# Its run is a string of long, low hops (#1271): a run is longer hops, not quicker legs. Each hop
# arcs HOP_HEIGHT up, its feet skimming HOP_SKIM over the ground where it comes down, so they never
# drag along it; its hind legs kick back as it takes off and its forelegs reach for the landing.
HOP_HEIGHT, HOP_SKIM = 0.18, 0.06
HOP_KICK, HOP_REACH, HOP_FOLD = 0.45, 0.35, 0.3


def hop():
    """A run of hops, posed on every frame as smooth waves, one hop a loop: the body rises and
    falls (lowest as it lands, t=0), pitching nose up as it takes off and down as it lands, the
    hind legs kicking back behind it and folding up under it in the air, the forelegs swinging
    forward to land."""
    poses = []
    for step in range(RUN_FRAMES + 1):
        t = step / RUN_FRAMES
        lap = 2.0 * math.pi * t
        rise = 0.5 - 0.5 * math.cos(lap)
        pitch = -0.10 * math.sin(lap)
        kick = HOP_KICK * math.sin(lap - 0.6)
        reach = HOP_REACH * math.sin(lap + 2.2)
        fold = HOP_FOLD * rise
        pose = {
            "root_loc": (0.0, HOP_SKIM + HOP_HEIGHT * rise, 0.0),
            "hips": (pitch, 0.0, 0.0),
            "neck": (-0.6 * pitch, 0.0, 0.0),
            "head": (-0.3 * pitch, 0.0, 0.0),
            "tail_01": (0.2 * rise, 0.0, 0.0),
        }
        clips._both(pose, "thigh", (kick - pitch, 0.0, 0.0))
        clips._both(pose, "shin", (fold, 0.0, 0.0))
        clips._both(pose, "hock", (-0.9 * fold, 0.0, 0.0))
        clips._both(pose, "upper_arm", (reach - pitch, 0.0, 0.0))
        clips._both(pose, "forearm", (-fold, 0.0, 0.0))
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)


def flop():
    """Its faint (#1271): it sways, catches itself once, then flops flat onto its belly, `BELLY_HEIGHT`
    down, its feet sliding out to the sides as its legs splay, its chin settling on the ground
    (a wolf's faint would drive its low head into it), its fronds drooping, and it keeps sinking
    into the ground's hold, rather than freezing there."""
    sway = {"root_loc": (0, -BELLY_HEIGHT * 0.12, 0), "spine_02": (0, 0, 0.06), "neck": (0.06, 0, 0),
            "head": (0.05, 0, -0.1)}
    clips._both(sway, "ear", (0.3, 0, 0))
    caught = {"root_loc": (0, -BELLY_HEIGHT * 0.05, 0), "spine_02": (0, 0, -0.03), "head": (-0.04, 0, 0.06)}
    clips._both(caught, "ear", (0.2, 0, 0))
    flat = {"root_loc": (0, -BELLY_HEIGHT * 0.9, 0), "neck": (0.06, 0, 0), "head": (0.06, 0, 0.12),
            "ear.L": (0.7, 0, 0.25), "ear.R": (0.7, 0, -0.25), "tail_01": (0.2, 0, 0.2)}
    # The belly lands and the body wobbles once, a soggy bounce.
    bounce = dict(flat, root_loc=(0, -BELLY_HEIGHT * 0.75, 0), head=(0.02, 0, 0.1))
    still = dict(flat, root_loc=(0, -BELLY_HEIGHT * 0.95, 0), head=(0.08, 0, 0.14))
    still["ear.L"], still["ear.R"] = (0.85, 0, 0.3), (0.85, 0, -0.3)
    steps = []
    for side, sign, late in (("L", 1.0, 0), ("R", -1.0, 2)):
        steps.append(legs.Step("front_paw." + side, 14 + late, 26 + late, (0.08 * sign, 0.0, 0.06), 0.03))
        steps.append(legs.Step("hind_paw." + side, 16 + late, 28 + late, (0.10 * sign, 0.0, -0.04), 0.03))
    return clips.Clip([(1, {}), (6, sway), (10, caught), (24, flat, "quart"), (28, bounce), (32, flat),
                       (50, still)], steps=steps)


# Where its feet lie while it sleeps (#1229), splayed out to the sides as its faint leaves them
# (the left one's; the right mirrors it): clips.sleep.
SQUAT = {"front_paw": (0.08, 0.0, 0.06), "hind_paw": (0.10, 0.0, -0.04)}


def squat(chest):
    """Its sleeping pose (#1229), at `chest` (0..1) of a breath: flat on its belly, `BELLY_HEIGHT`
    down, as calmly as its faint is limp, its chin on the ground (no lowered head, as a wolf's),
    its fronds laid back and its tail tucked to one side; the breath swells its back and lifts its
    chin a little."""
    return {"root_loc": (0, -BELLY_HEIGHT * 0.92, 0), "spine_02": (0.03 * chest, 0, 0), "neck": (0.06, 0, 0),
            "head": (0.06 - 0.02 * chest, 0, 0.04), "ear.L": (0.7, 0, 0.25), "ear.R": (0.7, 0, -0.25),
            "tail_01": (0.2, 0, 0.35)}


def _booming(t):
    """The held boom at `t` (0..1) of the loop: head raised, the chest
    pumping with each boom (CHANNEL_FRAMES / BOOM of them a loop), every wave leaving and
    returning to the pose at t=0 with no speed, so the wind-up, the seam and the release meet."""
    booms = CHANNEL_FRAMES // BOOM

    def wave(waves):
        return 0.5 - 0.5 * math.cos(2 * math.pi * waves * t)

    sway = math.sin(2 * math.pi * t) ** 3
    pose = {
        "root_loc": (0.0, 0.03 - 0.004 * wave(booms), 0.0),
        "hips": (-0.04, 0.0, 0.0),
        "spine_02": (-0.05 + 0.012 * wave(booms), 0.0, 0.0),
        "neck": (-0.12 - 0.008 * wave(booms), 0.0, 0.05 * sway),
        "head": (-0.10 - 0.012 * wave(booms), 0.0, -0.04 * sway),
        "tail_01": (0.15, 0.0, 0.0),
    }
    clips._both(pose, "ear", (-0.25 - 0.03 * wave(booms), 0.0, 0.0))
    return pose


def boom():
    """Its long attack (#1158, #1271) as the three clips the game plays in turn: it draws itself up
    and fills its throat (ChannelStart), booms on and on for as long as the attack lasts, the
    throat sac swelling with each boom (Channel), and lets the air out, sinking back and settling
    (ChannelEnd). Its feet stay planted: it booms where it sits."""
    held = _booming(0.0)
    gulp = {"root_loc": (0.0, -0.03, -0.02), "hips": (0.03, 0.0, 0.0), "neck": (0.08, 0.0, 0.0),
            "head": (0.05, 0.0, 0.0)}
    clips._both(gulp, "ear", (0.2, 0.0, 0.0))
    risen = dict(held, root_loc=(0.0, 0.045, 0.0), neck=(-0.16, 0.0, 0.0))
    start = clips.Clip([(1, {}), (6, gulp), (12, risen, "back"), (17, held), (clips.CHANNEL_START, held)])
    loop = clips.Clip([(step + 1, _booming(step / CHANNEL_FRAMES)) for step in range(CHANNEL_FRAMES + 1)],
                      loop=True)
    sag = {"root_loc": (0.0, -0.03, 0.0), "hips": (0.02, 0.0, 0.0), "neck": (0.06, 0.0, 0.0),
           "head": (0.04, 0.0, 0.0)}
    clips._both(sag, "ear", (0.25, 0.0, 0.0))
    end = clips.Clip([(1, held), (8, sag, "quart"), (18, {"root_loc": (0.0, 0.008, 0.0)}), (26, {})])
    return {"ChannelStart": start, "Channel": loop, "ChannelEnd": end}


def build(out):
    scene.reset(FPS)
    mats = palette(COLORS)
    skin = toad_body()
    skin.data.materials.append(mats["skin"])
    pieces = head_parts(skin, mats) + throat(mats) + back(skin, mats)
    symmetry.check(pieces)
    rig = quadruped.armature("OmbulumoRig", TOAD)
    points(rig, pieces)
    channel = boom()
    # The booms fall where the chest pumps highest, halfway between the loop's beats; the wind-up
    # and the release take the beat either side of them, so the pulse runs on across the clips.
    booms = [beat + BOOM // 2 + 1 for beat in range(-BOOM, CHANNEL_FRAMES + BOOM, BOOM)]
    beats = {
        "Idle": [70, 175],
        "Attack": [14],
        "ChannelStart": [clips.CHANNEL_START + booms[0]],
        "Channel": booms,
        "ChannelEnd": [booms[-2] - CHANNEL_FRAMES],
    }
    booming = pulse.Pulse(rig, "throat", THROAT, "neck", beats, BOOM_SWELL, BOOM_RISE, BOOM_FALL)
    scene.apply_scale([rig, skin] + pieces, SCALE)
    weights.bind(skin, rig, pieces, rigid_bones=("jaw", "ear.L", "ear.R", THROAT_BONE),
                 reweigh=turrets)
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, TOAD, clips.WALK, duty=0.35, fold=0.5, lift=0.25, curl=0.25,
                          roll=0.08),
        "Run": hop(),
        "Attack": leap(),
        "Hit": clips.hit(),
        "Faint": flop(),
        **channel,
        # No neck: the toad's head is near the ground already, and dips to it.
        "Feed": clips.feed(neck=0.18, head=-0.05, crouch=0.06, forepaws=0.06),
        "Sleep": clips.sleep(squat, SQUAT),
    }, SCALE, ground_meshes=[skin], overlays=[booming.beat])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    # The speeds the motion check runs the ground under the clips at (model skill).
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(sys.argv[sys.argv.index("--") + 1])
