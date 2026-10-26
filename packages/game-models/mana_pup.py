"""The mana pup (#1220): the young of the mana wolf, a round, soft quadruped with a big head, big
paws and big ears, its crystals only budding and a few wisps already hovering about it, rigged
and animated. Built on the mana wolf's way (packages/game-models/mana_wolf.py) from the shared
library in packages/game-models/lib/ (model skill); only its parameters and its own parts live here.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/mana_pup.py -- packages/game/assets/mana-pup/mana_pup.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes.

Blender is Z-up and the pup faces -Y (the game's +Z). Sizes are in the mana wolf's metres, so the
shared clips' moves fit it, shrunk by SCALE at the end to a pup's size beside the wolf.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import attachments, body, clips, eyes, metrics, muzzle, parts, quadruped, scene, surface, symmetry, weights, wisps  # noqa: E402
from lib.materials import palette  # noqa: E402

FPS = 30
# Half the mana wolf's length, and nearly its height to the tips of its big ears (the wolf's SCALE
# is 0.75 on a body as tall and much longer).
SCALE = 0.7
# Fewer triangles than the wolf's body: it's smaller on screen, and its forms are rounder; its lower
# jaw is part of it (#1194).
BODY_TRIANGLES = 7700

# The wolf's colours, the fur lighter and softer: a pup's coat before it darkens.
COLORS = {
    "fur": ((0.22, 0.26, 0.52, 1.0), 0.0),
    "light": ((0.78, 0.82, 0.98, 1.0), 0.0),
    "glow": ((0.05, 0.55, 1.0, 1.0), 1.0),
    "dark": ((0.03, 0.03, 0.06, 1.0), 0.0),
}

# A pup's proportions against the wolf's: a short, round trunk on stubby, puppy-short legs with big
# paws, a big round head on a short neck, a short muzzle, big ears and a short tail held up. Lowered
# on shorter legs (front and hind, about 15 %; #1307) for a puppy's stubby stance.
PUP = quadruped.Proportions(
    tail=[(0.0, 0.70, 1.06), (0.0, 0.60, 0.98), (0.0, 0.48, 0.90), (0.0, 0.38, 0.84)],
    hips=(0.0, 0.34, 0.80),
    waist=(0.0, 0.10, 0.83),
    chest=(0.0, -0.20, 0.86),
    head_base=(0.0, -0.40, 1.08),
    nose=(0.0, -0.98, 1.16),
    # The jaw turns at its joint (#1194), as the wolf's does: below and before the ear, about three
    # quarters of the head's length back from the nose, a little above the line of the lips.
    jaw=((0.0, -0.56, 1.14), (0.0, -0.92, 1.05)),
    ear=((0.15, -0.50, 1.38), (0.27, -0.47, 1.60)),
    scapula=(0.12, -0.12, 0.96),
    # The forearm is clearly shorter than the upper arm above it, as a canine's is (the owner, on
    # #1297; #1299, lib/dimensions.py). Both leg chains are shortened by about 15 % (#1307).
    front_leg=[(0.17, -0.24, 0.76), (0.20, -0.21, 0.42), (0.20, -0.26, 0.19), (0.20, -0.38, 0.06)],
    hind_leg=[
        (0.17, 0.32, 0.74),
        (0.20, 0.16, 0.48),
        (0.20, 0.36, 0.25),
        (0.20, 0.32, 0.08),
        (0.20, 0.21, 0.06),
    ],
)
# Its proportions (#1072), measured from the build first shown to the owner on #1220: a change that
# drifts from them fails the build (lib/metrics.py), so a derpy edit shows as numbers. Against the
# wolf's: a bigger, rounder head on a short trunk on stubby legs, a short muzzle, and big round eyes
# set forward on the face (the blind review on #1249). leg/body updated for the shorter legs (#1307),
# and nose width/muzzle width with them: the same nose, but the body's reduction to its triangle
# budget lays the few vertices at the nose's tip differently once the legs change.
REFERENCE = {
    "head/body": 1.519,
    "head height/length": 0.775,
    "head width/length": 0.671,
    "leg/body": 1.469,
    "ear/head": 0.306,
    "tail/body": 1.079,
    "eye spacing/head width": 0.404,
    # The eyes mirror each other: level, side by side, equally far out.
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
    "muzzle/head": 0.287,
    "muzzle depth/length": 0.832,
    "muzzle width/head width": 0.327,
    "nose width/muzzle width": 0.530,
    "jaw depth/muzzle depth": 0.364,
    "jaw width/muzzle width": 0.785,
    # The lower jaw runs back to its joint (#1194), as a mandible does: longer than the muzzle.
    "jaw/muzzle": 2.077,
    "chin reach/muzzle": 0.762,
}

# A short snout, its stop high on a round brow and its tip blunt, the lower jaw small under it,
# turning at the jaw's joint (#1194). Its mouth's slit is cut twice as thick as the wolf's: its big
# round skull and full cheeks swell over the short muzzle, and through a thinner slit they kept the
# lips joined down the middle of the mouth, skin that stretched in streaks between the jaws as they
# opened (#1302).
SNOUT = muzzle.Snout(stop=(-0.80, 1.23), tip=(-1.02, 1.14), radius=0.085, joint=PUP.jaw[0][1:], taper=0.78,
                     stop_depth=0.09, lip=0.03, jaw_depth=0.55, jaw_width=1.0, chin=1.0,
                     slit=0.012)

# Where the tail's form starts, inside the haunches.
TAIL_ROOT = (0.0, 0.30, 0.82)

# How tall the pup stands at its belly: the faint and the sleep sink it this far.
HIP_HEIGHT = 0.48
# Its shorter legs (#1307) reach less far: its forepaws lie closer in when it lies down (the faint
# and the sleep, clips.CURLED), and step out less far into a long attack's braced stance
# (clips.BRACE).
FOREPAWS_LYING = 0.38
CURLED = dict(clips.CURLED, front_paw=(0.0, 0.0, FOREPAWS_LYING))
BRACE = {"front_paw": (0.06, 0.0, 0.14), "hind_paw": (0.04, 0.0, -0.06)}
# The low trunk sits close to the leg bones: its belly must follow the spine when they fold.
TORSO_WEIGHT_HEIGHTS = (0.45, 0.75)

# The game's speeds at the model's size (metres a second), as for the wolf: a wild monster glides a
# tile (sqrt(3) apart) in 0.8 s, a companion follows at a tile every 0.3 s. It trots where the wolf
# walks, its paws on the ground for less of each cycle, which covers two thirds of a tile as the
# wolf's does; its gallop takes quicker strides than the wolf's, a tile a cycle, landing lightly
# (its paws down for a fifth of it) with its back flexing less.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * 2 / 3, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

# Three wisps hovering about its head and back (lib/wisps.py): the start of the crown its elders
# wear, gathering into a ring above its head as it pounces and while it holds a long attack, over
# the tips of its big ears. On their way to it and back they fly over the crest buds and the ears,
# CROWN_RISE above the ring or their spot, whichever is higher (#1182).
WISPS = [(0.30, -0.34, 1.30), (-0.34, 0.08, 1.24), (0.0, 0.30, 1.36)]
CROWN_CENTER, CROWN_RADIUS, CROWN_BONE, CROWN_RISE = (0.0, -0.56, 1.74), 0.3, "head", 0.2
CROWN = wisps.Gather("Attack", 1, 12, 21, 31, CROWN_CENTER, CROWN_RADIUS, spin=0.06, stagger=2, bone=CROWN_BONE,
                     rise=CROWN_RISE)
CHANNEL_FRAMES = 60
CHANNEL_SPIN = 2.0 * math.pi / CHANNEL_FRAMES
HELD = CHANNEL_SPIN * (clips.CHANNEL_START - 1)
CHANNEL_CROWN = [
    wisps.Gather("ChannelStart", 1, 16, None, None, CROWN_CENTER, CROWN_RADIUS, spin=CHANNEL_SPIN, stagger=2,
                 bone=CROWN_BONE, rise=CROWN_RISE),
    wisps.Gather("Channel", 1, None, None, None, CROWN_CENTER, CROWN_RADIUS, spin=CHANNEL_SPIN, turn=HELD,
                 bone=CROWN_BONE),
    wisps.Gather("ChannelEnd", 1, None, 4, 20, CROWN_CENTER, CROWN_RADIUS, spin=CHANNEL_SPIN, turn=HELD,
                 bone=CROWN_BONE, rise=CROWN_RISE),
]


def mirror(point, sign):
    return (point[0] * sign, point[1], point[2])


def pup_body():
    """Soft, round forms: a round chest and belly, plump haunches, a big round head with full
    cheeks and a short muzzle, a fluffy tail and big padded paws with toes."""
    blob = body.Blob("ManaPup")
    blob.ellipsoid((0.0, -0.16, 0.82), (0.26, 0.26, 0.27))
    blob.ellipsoid((0.0, 0.08, 0.80), (0.25, 0.25, 0.25))
    blob.ellipsoid((0.0, 0.30, 0.82), (0.23, 0.19, 0.23))
    blob.capsule((0.0, -0.26, 0.92), (0.0, -0.40, 1.08), 0.18)
    # A full throat under the head, so the head grows out of the neck rather than sitting on it.
    blob.ellipsoid((0.0, -0.44, 1.00), (0.16, 0.17, 0.17))
    # A big round skull with a domed brow, and the snout's stop and short upper muzzle.
    blob.ellipsoid((0.0, -0.56, 1.20), (0.27, 0.27, 0.25))
    SNOUT.upper(blob)
    SNOUT.lower(blob)
    # A short, fluffy tail, starting inside the haunches so its root melts into them (as the
    # wolf's, #1171).
    blob.tube([TAIL_ROOT, *reversed(PUP.tail)], [0.10, 0.10, 0.14, 0.13, 0.07])
    for sign in (1, -1):
        blob.ellipsoid((0.14 * sign, -0.70, 1.12), (0.11, 0.11, 0.10))
        front = [mirror(p, sign) for p in PUP.front_leg]
        blob.limb([front[0], front[1], front[2], (0.20 * sign, -0.32, 0.07)], [0.13, 0.10, 0.085, 0.085])
        hind = [mirror(p, sign) for p in PUP.hind_leg]
        blob.limb(hind[:4], [0.15, 0.11, 0.09, 0.085])
        # The haunch: a round, plump thigh.
        blob.ellipsoid(mirror((0.16, 0.28, 0.68), sign), (0.14, 0.11, 0.13), (0.04 * sign, -0.2, -0.34))
        for paw_y, toe_y in ((-0.32, -0.40), (0.30, 0.22)):
            blob.ellipsoid((0.20 * sign, paw_y, 0.065), (0.095, 0.115, 0.065))
            for toe_x in (-0.06, -0.02, 0.02, 0.06):
                blob.ball(((0.20 + toe_x) * sign, toe_y, 0.045), 0.04)
    return blob.mesh(BODY_TRIANGLES)


def head_parts(skin, mats):
    """The snout's jaw, nose, mouth and small fangs, big ears with pale insides, and big round
    eyes."""
    made = SNOUT.parts(mats, "head", "jaw")
    for sign in (1, -1):
        side = "L" if sign == 1 else "R"
        base, tip = (mirror(p, sign) for p in PUP.ear)
        out = tuple(t - b for t, b in zip(tip, base))
        center = tuple(b + o * 0.5 for b, o in zip(base, out))
        rotation = parts.pointing(out, up=(0.0, -1.0, 0.0))
        made.append(parts.part("cone", "Ear." + side, center, (0.15, 0.05, 0.25), rotation, mats["fur"],
                               "ear." + side, vertices=12, radius1=1.0, radius2=0.0, depth=1.0))
        inner = (center[0], center[1] - 0.025, center[2] - 0.01)
        made.append(parts.part("cone", "InnerEar." + side, inner, (0.10, 0.02, 0.19), rotation,
                               mats["light"], "ear." + side, vertices=10, radius1=1.0, radius2=0.0, depth=1.0))
        made += eyes.eye(skin, "Eye." + side, (0.10 * sign, -0.82, 1.24), (0.03 * sign, -1.0, 0.05), 0.09,
                         {"dark": mats["dark"], "glow": mats["glow"], "light": mats["light"], "skin": mats["fur"]},
                         "head", almond=1.0, tilt=0.0, brow=math.radians(-20),
                         # A pup's soft, small brow, not a predator's heavy ridge (the owner, on #1249).
                         brow_size=0.5)
    return made


def points(rig, pieces):
    """The attachment points (#1007): the eyes, and its one centre of attack, the mouth between
    the fangs, which moves with the head."""
    sides = {side: [piece for piece in pieces if piece.name.startswith("Eye.%s." % side)] for side in ("L", "R")}
    attachments.add(rig, {side: (eyes.spot(eye), "head", eyes.look(eye)) for side, eye in sides.items()},
                    [((0.0, -0.92, 1.08), "head")])


def paws(mats):
    """Tiny mana-blue claws along the front of each big paw."""
    made = []
    for sign, side in ((1, "L"), (-1, "R")):
        for bone, toe_y in (("front_paw", -0.43), ("hind_paw", 0.17)):
            made += parts.claws("Claw.%s.%s" % (bone, side), (0.20 * sign, toe_y, 0.04), (0.0, -1.0, 0.0), 4,
                                0.12, 0.035, mats["glow"], "%s.%s" % (bone, side))
    return made


def fur(mats):
    """Fluffy cheeks and a tuft on the crown of the head."""
    made = []
    for sign in (1, -1):
        for index, z in enumerate((1.16, 1.09)):
            made.append(parts.tuft("Cheek.%d.%d" % (sign, index), (0.21 * sign, -0.70, z),
                                   (0.6 * sign, 1.0, -0.2 - 0.2 * index), 0.09, 0.06, 0.5, mats["fur"], "head"))
    for index, sign in enumerate((1, -1, 0)):
        made.append(parts.tuft("Crown.%d" % index, (0.03 * sign, -0.52, 1.44), (0.4 * sign, 0.6, 1.0),
                               0.09 - 0.02 * abs(sign), 0.05, 0.7, mats["fur"], "head", up=(0.0, 1.0, 0.0)))
    return made


def magic(skin, mats):
    """The mana, only budding: a small crystal on the brow and a row of crystal buds down the back
    where its crest will grow, a bud at the tail's tip, one glowing vein down each flank, a rune on
    each shoulder, and wisps hovering about it."""
    glow = mats["glow"]
    made = [parts.crystal("Brow", surface.onto(skin, (0.0, -0.72, 1.41), -0.02), (0.0, -0.1, 1.0), 0.09, glow,
                          "head", width=0.3)]
    crest = (((0.0, -0.10, 1.08), 0.12, "spine_02"), ((0.0, 0.10, 1.05), 0.10, "spine_01"),
             ((0.0, 0.30, 1.04), 0.08, "hips"))
    for index, (guess, height, bone) in enumerate(crest):
        made.append(parts.crystal("Crest.%d" % index, surface.onto(skin, guess, -0.02), (0.0, 0.35, 1.0), height,
                                  glow, bone, width=0.3))
    made.append(parts.crystal("TailTip", (0.0, 0.71, 1.12), (0.0, 0.5, 1.0), 0.1, glow, "tail_04", width=0.3))
    for sign in (1, -1):
        side = "L" if sign == 1 else "R"
        start = (0.05 * sign, -0.06, 1.06)
        made.append(surface.vein(skin, "Vein.%s" % side,
                                 [start, (0.18 * sign, 0.02, 0.94), (0.24 * sign, 0.12, 0.76)], 0.006, glow,
                                 taper=0.45))
        made += surface.rune(skin, "Rune.%s" % side, "eye", mirror((0.25, -0.18, 0.78), sign), (0.0, 1.0, 0.0),
                             (0.0, 0.0, 1.0), 0.13, 0.008, glow)
    for index, spot in enumerate(WISPS):
        made.append(parts.part("uv_sphere", "Wisp.%d" % index, spot, (0.026, 0.026, 0.055), mat=glow,
                               bone=wisps.PREFIX + str(index), segments=8, ring_count=5))
    return made


def build(out):
    scene.reset(FPS)
    mats = palette(COLORS)
    skin = pup_body()
    skin.data.materials.append(mats["fur"])
    pieces = head_parts(skin, mats) + fur(mats) + paws(mats) + magic(skin, mats)
    symmetry.check(pieces)
    rig = quadruped.armature("ManaPupRig", PUP)
    points(rig, pieces)
    drifting = wisps.Wisps(rig, WISPS, [CROWN, *CHANNEL_CROWN])
    scene.apply_scale([rig, skin] + pieces, SCALE)

    def reweigh(body):
        quadruped.bind_torso(body, rig, *(height * SCALE for height in TORSO_WEIGHT_HEIGHTS))
        SNOUT.bind_jaw(body, "jaw", SCALE)

    weights.bind(skin, rig, pieces, rigid_bones=("jaw", "ear.L", "ear.R", *drifting.names),
                 reweigh=reweigh)
    clips.animate(rig, {
        "Idle": clips.idle(),
        # With the shorter forearm (#1299), its paws stay down a little longer and the forearm folds a
        # little more, so the swing back stays smooth (the motion check's jitter).
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, PUP, clips.TROT, duty=0.32, fold=0.65, lift=0.22, curl=0.6,
                          roll=0.05),
        # Its shorter legs (#1307) swing through wider angles at the same speed: its paws touch down
        # for less of the gallop, so the swing back stays smooth (the motion check's jitter).
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, PUP, clips.GALLOP, duty=0.15, fold=0.4, spine_flex=0.04,
                         planted=False),
        "Attack": clips.attack(),
        "Hit": clips.hit(),
        "Faint": clips.faint(HIP_HEIGHT, forepaws=FOREPAWS_LYING),
        **clips.channel(CHANNEL_FRAMES, brace=BRACE),
        # A pup's short neck reaches the ground with less of a bend.
        "Feed": clips.feed(neck=0.5, head=0.0, crouch=0.25, forepaws=0.2),
        "Sleep": clips.sleep(clips.curled(HIP_HEIGHT), paws=CURLED),
    }, SCALE, ground_meshes=[skin],  # the body, with every part joined into it by weights.bind
        overlays=[drifting.drift])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    # The speeds the motion check runs the ground under the clips at (model skill).
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(sys.argv[sys.argv.index("--") + 1])
