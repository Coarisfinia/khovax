"""The mana wolf (#990, #995): a wolf-like quadruped with a mane, mana crystals, glowing veins and
runes, rigged and animated. Only its parameters and its own parts live here; the building blocks
are the shared library in packages/game-models/lib/ (model skill).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/mana_wolf.py -- packages/game/assets/mana-wolf/mana_wolf.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes.

Blender is Z-up and the wolf faces -Y (the game's +Z). Sizes are a large wolf's, in metres,
shrunk by SCALE at the end to stand on one hex tile.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import attachments, body, clips, eyes, metrics, parts, quadruped, scene, surface, symmetry, weights, wisps  # noqa: E402
from lib.materials import palette  # noqa: E402

FPS = 30
SCALE = 0.75
# The body's budget before its parts: a monster seen full-screen on its codex page, and several
# at once on a phone.
BODY_TRIANGLES = 9000

COLORS = {
    "fur": ((0.11, 0.12, 0.27, 1.0), 0.0),
    "light": ((0.62, 0.68, 0.92, 1.0), 0.0),
    "glow": ((0.05, 0.55, 1.0, 1.0), 1.0),
    "dark": ((0.03, 0.03, 0.06, 1.0), 0.0),
}

WOLF = quadruped.Proportions(
    tail=[(0.0, 1.62, 0.66), (0.0, 1.38, 0.84), (0.0, 1.12, 0.98), (0.0, 0.86, 1.04)],
    hips=(0.0, 0.62, 1.02),
    waist=(0.0, 0.32, 1.05),
    chest=(0.0, -0.22, 1.10),
    head_base=(0.0, -0.66, 1.38),
    nose=(0.0, -1.26, 1.35),
    jaw=((0.0, -0.80, 1.28), (0.0, -1.18, 1.23)),
    ear=((0.10, -0.70, 1.58), (0.13, -0.68, 1.80)),
    scapula=(0.12, -0.18, 1.22),
    front_leg=[(0.20, -0.40, 0.98), (0.23, -0.36, 0.58), (0.23, -0.42, 0.18), (0.23, -0.56, 0.06)],
    hind_leg=[
        (0.20, 0.56, 0.96),
        (0.24, 0.36, 0.62),
        (0.24, 0.64, 0.30),
        (0.24, 0.58, 0.08),
        (0.24, 0.44, 0.06),
    ],
)
# The approved proportions (#1072), measured from the version the owner approved on #995: a change
# that drifts from them fails the build (lib/metrics.py), so a derpy edit shows as numbers.
REFERENCE = {
    "head/body": 0.866,
    "head height/length": 0.742,
    "head width/length": 0.558,
    "leg/body": 1.177,
    "ear/head": 0.318,
    "tail/body": 1.512,
    # The eyes moved in halfway toward a close-set test on the owner's word (#1084).
    "eye spacing/head width": 0.429,
    # The eyes mirror each other: level, side by side, equally far out.
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

# How tall the wolf stands at the hips: the faint sinks it this far.
HIP_HEIGHT = 0.69

# The game's speeds at the model's size (metres a second): a wild monster glides a tile (sqrt(3)
# apart) in 0.8 s, a companion follows at a tile every 0.3 s. A walk cycle covers two thirds of a
# tile (short, quick steps: a long stride at this speed would swing the legs past what a wolf's
# reach allows), a gallop cycle one and a quarter (its free-swinging legs then barely slide). The
# strides are what a whole number of frames covers, at the model's unscaled size.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * 2 / 3, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * 1.25, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

# The wisps drifting around the body (lib/wisps.py, #1103): where each floats and the bone it goes with.
WISPS = [((0.38, 0.15, 1.45), "spine_01"), ((-0.34, -0.12, 1.52), "spine_02"), ((0.0, 0.95, 1.38), "tail_01"),
         ((0.3, -0.62, 1.72), "neck"), ((-0.3, 0.62, 1.32), "hips"), ((0.0, 1.78, 0.86), "tail_04")]


def mirror(point, sign):
    return (point[0] * sign, point[1], point[2])


def wolf_body():
    """Soft forms: a deep chest, a tucked waist, round haunches and hocks, a broad head with
    cheeks and a long muzzle, a bushy tail and padded paws with toes."""
    blob = body.Blob("ManaWolf")
    blob.ellipsoid((0.0, -0.25, 1.03), (0.25, 0.30, 0.33))
    blob.ellipsoid((0.0, 0.05, 1.04), (0.23, 0.30, 0.27))
    blob.ellipsoid((0.0, 0.33, 1.06), (0.19, 0.20, 0.20))
    blob.ellipsoid((0.0, 0.58, 1.03), (0.21, 0.22, 0.22))
    blob.capsule((0.0, -0.40, 1.16), (0.0, -0.66, 1.38), 0.19)
    blob.ellipsoid((0.0, -0.52, 1.08), (0.15, 0.15, 0.17))
    # A wedge of a head: a flat skull, a brow that steps down to the muzzle, and a muzzle that
    # narrows to the nose under a straight bridge.
    blob.ellipsoid((0.0, -0.78, 1.47), (0.17, 0.22, 0.14))
    blob.ellipsoid((0.0, -0.86, 1.52), (0.12, 0.08, 0.06))
    blob.capsule((0.0, -0.90, 1.42), (0.0, -1.08, 1.40), 0.075)
    blob.capsule((0.0, -1.08, 1.40), (0.0, -1.22, 1.37), 0.05)
    blob.capsule((0.0, -0.92, 1.47), (0.0, -1.20, 1.41), 0.03)
    blob.ellipsoid((0.0, -1.00, 1.35), (0.055, 0.15, 0.04))
    blob.limb(list(reversed(WOLF.tail)), [0.10, 0.15, 0.13, 0.06])
    for sign in (1, -1):
        blob.ellipsoid((0.1 * sign, -0.84, 1.41), (0.08, 0.11, 0.075))
        front = [mirror(p, sign) for p in WOLF.front_leg]
        blob.limb([front[0], front[1], front[2], (0.23 * sign, -0.50, 0.07)], [0.13, 0.085, 0.06, 0.065])
        blob.ellipsoid(mirror((0.2, -0.36, 0.84), sign), (0.2, 0.1, 0.13), (0.03 * sign, 0.04, -0.4))
        hind = [mirror(p, sign) for p in WOLF.hind_leg]
        blob.limb(hind[:4], [0.15, 0.10, 0.07, 0.055])
        # The haunch and the calf: round muscle over the thigh and behind the shin.
        blob.ellipsoid(mirror((0.18, 0.50, 0.84), sign), (0.24, 0.12, 0.17), (0.04 * sign, -0.2, -0.34))
        blob.ellipsoid(mirror((0.24, 0.48, 0.50), sign), (0.14, 0.075, 0.08), (0.0, 0.28, -0.32))
        for paw_y, toe_y in ((-0.52, -0.60), (0.48, 0.40)):
            blob.ellipsoid((0.23 * sign, paw_y, 0.06), (0.075, 0.10, 0.05))
            for toe_x in (-0.055, -0.02, 0.02, 0.055):
                blob.ball(((0.23 + toe_x) * sign, toe_y, 0.04), 0.032)
    return blob.mesh(BODY_TRIANGLES)


def head_parts(skin, mats):
    """Jaw, nose, fangs, ears with pale insides, and the eyes."""
    made = [
        # A lean lower jaw narrowing to the chin, and an angled nose pad on the muzzle's tip.
        parts.part("cone", "Jaw", (0.0, -1.0, 1.33), (0.052, 0.028, 0.34), parts.pointing((0.0, -1.0, -0.12)),
                   mats["fur"], "jaw", vertices=12, radius1=1.0, radius2=0.35, depth=1.0),
        parts.part("uv_sphere", "Nose", (0.0, -1.245, 1.395), (0.042, 0.03, 0.026), (0.45, 0, 0), mats["dark"],
                   "head", segments=12, ring_count=6),
    ]
    for sign in (1, -1):
        for name, base, bone in (("Fang", (0.035, -1.15, 1.345), "head"), ("LowFang", (0.03, -1.10, 1.325), "jaw")):
            direction = (0.0, 0.0, -1.0) if bone == "head" else (0.0, 0.0, 1.0)
            made.append(parts.crystal("%s.%d" % (name, sign), mirror(base, sign), direction, 0.04,
                                      mats["light"], bone, width=0.25, sides=5))
        side = "L" if sign == 1 else "R"
        base, tip = (mirror(p, sign) for p in WOLF.ear)
        out = tuple(t - b for t, b in zip(tip, base))
        center = tuple(b + o * 0.5 for b, o in zip(base, out))
        rotation = parts.pointing(out, up=(0.0, -1.0, 0.0))
        made.append(parts.part("cone", "Ear." + side, center, (0.10, 0.045, 0.24), rotation, mats["fur"],
                               "ear." + side, vertices=12, radius1=1.0, radius2=0.0, depth=1.0))
        inner = (center[0], center[1] - 0.02, center[2] - 0.01)
        made.append(parts.part("cone", "InnerEar." + side, inner, (0.065, 0.02, 0.18), rotation,
                               mats["light"], "ear." + side, vertices=10, radius1=1.0, radius2=0.0, depth=1.0))
        made += eyes.eye(skin, "Eye." + side, (0.07 * sign, -0.94, 1.505), (0.2 * sign, -1.0, 0.05), 0.055,
                         {"dark": mats["dark"], "glow": mats["glow"], "light": mats["light"], "skin": mats["fur"]},
                         "head", almond=0.5, tilt=math.radians(14), brow=math.radians(18))
    return made


def points(rig, pieces):
    """The attachment points (#1007): the eyes, and its one centre of attack, the mouth between
    the fangs, which moves with the head."""
    sides = {side: [piece for piece in pieces if piece.name.startswith("Eye.%s." % side)] for side in ("L", "R")}
    attachments.add(rig, {side: (eyes.spot(eye), "head") for side, eye in sides.items()},
                    [((0.0, -1.14, 1.32), "head")])


def paws(mats):
    """Small mana-blue claws along the front of each paw."""
    made = []
    for sign, side in ((1, "L"), (-1, "R")):
        for bone, toe_y in (("front_paw", -0.625), ("hind_paw", 0.375)):
            made += parts.claws("Claw.%s.%s" % (bone, side), (0.23 * sign, toe_y, 0.035), (0.0, -1.0, 0.0), 4,
                                0.11, 0.05, mats["glow"], "%s.%s" % (bone, side))
    return made


def fur(mats):
    """A pale ruff under the throat and tufts on the cheeks."""
    made = []
    for index, x in enumerate((-0.1, -0.04, 0.04, 0.1)):
        made.append(parts.tuft("Ruff.%d" % index, (x, -0.55, 0.95), (x, 0.35, -1.0), 0.2, 0.08, 0.5,
                               mats["light"], "neck", up=(0.0, -1.0, 0.0)))
    for sign in (1, -1):
        for index, z in enumerate((1.42, 1.36)):
            made.append(parts.tuft("Cheek.%d.%d" % (sign, index), (0.15 * sign, -0.80, z),
                                   (0.6 * sign, 1.0, -0.2 - 0.2 * index), 0.1, 0.06, 0.5, mats["fur"], "head"))
    return made


def magic(skin, mats):
    """The mana: a crest of crystals with glowing veins running from them, crystals on the brow,
    shoulders and tail tip, runes on the shoulders, ribs and haunches, rune bands on the
    legs, and wisps drifting around the body."""
    glow = mats["glow"]
    made = []
    crest = (((0.0, -0.28, 1.33), 0.50, "spine_02"), ((0.0, -0.02, 1.30), 0.42, "spine_02"),
             ((0.0, 0.24, 1.26), 0.34, "spine_01"), ((0.0, 0.48, 1.24), 0.24, "hips"))
    for index, (guess, height, bone) in enumerate(crest):
        base = surface.onto(skin, guess, -0.03)
        made.append(parts.crystal("Crest.%d" % index, base, (0.0, 0.35, 1.0), height, glow, bone))
        for sign in (1, -1):
            side_base = surface.onto(skin, (0.13 * sign, guess[1] + 0.06, guess[2] - 0.06), -0.02)
            made.append(parts.crystal("Flank.%d.%d" % (index, sign), side_base, (0.6 * sign, 0.3, 1.0),
                                      height * 0.45, glow, bone))
            # Veins running from the crystal down the flank, forking once.
            start = (0.05 * sign, guess[1], guess[2] - 0.02)
            mid = (0.2 * sign, guess[1] + 0.05, guess[2] - 0.2)
            made.append(surface.vein(skin, "Vein.%d.%d" % (index, sign),
                                     [start, mid, (0.27 * sign, guess[1] + 0.02, guess[2] - 0.42)], 0.0065, glow))
            made.append(surface.vein(skin, "Vein.%d.%d.b" % (index, sign),
                                     [mid, (0.26 * sign, guess[1] + 0.14, guess[2] - 0.3)], 0.005, glow))
    made.append(parts.crystal("Brow", surface.onto(skin, (0.0, -0.78, 1.62), -0.02), (0.0, 0.45, 1.0),
                              0.17, glow, "head"))
    for sign in (0, 1, -1):
        made.append(parts.crystal("TailTip.%d" % sign, (0.03 * sign, 1.58, 0.70), (0.3 * sign, 1.0, -0.2),
                                  0.26 - 0.08 * abs(sign), glow, "tail_04"))
    for sign in (1, -1):
        side = "L" if sign == 1 else "R"
        # The same axes on both sides: the right flank shows the left one's runes mirrored.
        right = (0.0, 1.0, 0.0)
        for glyph, center, size in (("eye", (0.27, -0.33, 0.95), 0.2), ("chevrons", (0.26, 0.06, 0.99), 0.18),
                                    ("fork", (0.29, 0.52, 0.86), 0.2)):
            made += surface.rune(skin, "Rune.%s.%s" % (glyph, side), glyph, mirror(center, sign), right,
                                 (0.0, 0.0, 1.0), size, 0.009, glow)
        for leg, joint, bone in ((WOLF.front_leg, 1, "forearm"), (WOLF.hind_leg, 2, "hock")):
            for share, radius in ((0.55, 0.075), (0.75, 0.068)):
                a, b = leg[joint], leg[joint + 1]
                spot = mirror(tuple(x + (y - x) * share for x, y in zip(a, b)), sign)
                made.append(parts.part("torus", "Band.%s.%s.%s" % (bone, share, side), spot, (1, 1, 1), mat=glow,
                                       bone="%s.%s" % (bone, side), major_radius=radius, minor_radius=0.011,
                                       major_segments=16, minor_segments=4))
    for index, (spot, _bone) in enumerate(WISPS):
        made.append(parts.part("uv_sphere", "Wisp.%d" % index, spot, (0.022, 0.022, 0.05), mat=glow,
                               bone=wisps.PREFIX + str(index), segments=8, ring_count=5))
    return made


def build(out):
    scene.reset(FPS)
    mats = palette(COLORS)
    skin = wolf_body()
    skin.data.materials.append(mats["fur"])
    pieces = head_parts(skin, mats) + fur(mats) + paws(mats) + magic(skin, mats)
    symmetry.check(pieces)
    rig = quadruped.armature("ManaWolfRig", WOLF)
    points(rig, pieces)
    drifting = wisps.Wisps(rig, WISPS)
    scene.apply_scale([rig, skin] + pieces, SCALE)
    weights.bind(skin, rig, pieces, rigid_bones=("jaw", "ear.L", "ear.R", *drifting.names))
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, WOLF, clips.WALK, duty=0.4, fold=0.6, lift=0.2, curl=0.6,
                          roll=0.06),
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, WOLF, clips.GALLOP, duty=0.3, fold=0.5, spine_flex=0.06,
                         planted=False),
        "Attack": clips.attack(),
        "Hit": clips.hit(),
        "Faint": clips.faint(HIP_HEIGHT),
    }, SCALE, ground_meshes=[skin],  # the body, with every part joined into it by weights.bind
        chains=clips.FOLLOW | drifting.follow(), overlays=[drifting.drift])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    # The speeds the motion check runs the ground under the clips at (model skill).
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(sys.argv[sys.argv.index("--") + 1])
