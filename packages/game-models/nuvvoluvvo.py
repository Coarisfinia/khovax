"""Nuvvoluvvo (#1620): the dream realm's big, round sleeper, a plump, low beast in pale dusk blue
with long floppy ears, a paler belly and a patch of our own night sky on its fur. Its mesh, colour
and rig come from the owner's generated model (`sources/nuvvoluvvo.glb`, made by import_source.py
from the download, its rig adopted by lib/rigged.py and fitted to its hex as a regular monster:
see the asset's SOURCE.md). This script:

- **paints it anew** (lib/repaint.py): the generator's paint is a patchwork of islands in a dozen
  shades of one blue, with a few blotchy painted stars on its back. Each texel takes the kind of
  paint it had (fur, belly or eye), settled by the texels around it on the body, so every area is
  one flat, even colour for the cel shading; the painted stars go;
- **gives it our stars** (lib/starfield.py): a patch of night sky from a fixed seed, every star
  one of the generator's two fixed shapes, where `STARS` places it (STARS_AT: along its back, or
  on its flanks), softly fading into the fur;
- **swaps in our eyes** (lib/marked_eyes.py): its painted eyes mark where ours go, with lids that
  blink in Idle and stay shut while it sleeps and rolls over;
- **names the adopted bones** to the library's quadruped scheme; the generator's left ear chain
  was regrown toward the muzzle by the import (it found no part of its own for it), so the left
  ear is rigged as the right one mirrored, bones and weights;
- **animates** every creature clip with the library's clips, its legs' share of them scaled
  down to its short legs, except its gaits: it bounces along on smooth waves (paddle), its legs
  paddling in pairs. And `RollOver`, the sleeper turning over in its sleep: onto its back, its
  paws in the air, and back again.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/nuvvoluvvo.py -- packages/game/assets/nuvvoluvvo/nuvvoluvvo.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py), or `STARS=flanks` for the other placement of its stars.

Blender is Z-up and it faces -Y (the game's +Z); its left is +X. The source is already at the
game's size, so its metres are the clips' unscaled ones (SCALE 1).
"""

import math
import os
import sys

import bpy
import numpy
from mathutils import Vector, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import (adopted, attachments, clips, legs, marked_eyes, materials, metrics, repaint, rigged,  # noqa: E402
                 scene, starfield, tuning)

SOURCE = os.path.join(HERE, "sources", "nuvvoluvvo.glb")
FPS = 30
SCALE = 1.0

# --- The paint ---------------------------------------------------------------------------------
# The texture's size (texels a side), the generator's atlas at the source's size; the stars' glow
# is coarser, as they are soft.
TEXTURE = 1024
GLOW_TEXTURE = 512
# The kinds of paint the generator laid down, told apart by its colour (sRGB, 0..1): the eyes'
# dark (which lib/marked_eyes.py finds and paints over), their white glint, the painted stars'
# pale yellow, the paler belly and muzzle, and the fur, everything else. Each kind's flat colour:
# the mean of what the generator painted as that kind (a touch more saturated for the fur), the eye
# dark enough for lib/marked_eyes.py to find (its DARK_VALUE).
DARK_BELOW, WHITE_ABOVE, BELLY_ABOVE = 0.3, 0.82, 0.68
YELLOW = 0.05
FUR = (0.55, 0.62, 0.71)
BELLY = (0.70, 0.76, 0.81)
EYE = (0.08, 0.09, 0.13)
# The paint is settled in cubes this wide (metres): each texel takes the kind most of the texels
# in its cube have, so a speck of another shade inside an area goes.
CUBE = 0.012
# The belly and muzzle never face up more than this (the up part of the normal): the painted stars'
# pale rims on its back are as pale as the belly, but they're fur.
BELLY_FACING = 0.5

# The night sky: a panorama around the trunk's middle (STARS_MIDDLE, metres), mapped onto the fur
# where `STARS` places it (all of it but its eyes, by default: the owner, on #1730), as on the
# starry egg (#1635): its size, seed and stars, sizes in
# radians seen from the middle.
SKY_WIDTH, SKY_HEIGHT = 1024, 512
SEED = 1620
STAR_COUNT = 160
SMALLEST, LARGEST = 0.030, 0.070
SPARKLES = 10
RAY = 0.17
POLAR = 0.98
STARS_MIDDLE = (0.0, 0.03, 0.28)
# How much the sky glows on its own, so its stars read in the shade of the cel shading.
SKY_GLOW = 0.8
# Where the patch lies (STARS_AT), as smooth steps from 0 to 1 over (from, to): the trunk only,
# between the shoulders and the rump (Y), and for `back` the faces looking up (their normal's Z),
# for `flanks` an oval on each side (its middle's Y and Z, and its half length and height).
# `all` covers everything but the eyes.
TRUNK = ((-0.30, -0.22), (0.42, 0.34))
BACK = (0.30, 0.62)
FLANK = (0.04, 0.33, 0.27, 0.10)
FLANK_EDGE = 0.35
STARS_AT = ("all", "back", "flanks")
STARS = "all"

# --- The rig -----------------------------------------------------------------------------------
# The adopted rig's names (lib/rigged.py) to the library's quadruped scheme the clips key: the
# trunk is the hips and two spine bones, then the neck (the generator's chest bone, which the
# bones between it and the skull join) and the head; each long floppy ear two bones; each foreleg
# an upper arm, a forearm and the paw (its short pastern joined into it), each hind leg a thigh, a
# shin, a hock and the paw (the empty bone above it joined in); the tail four bones.
RENAMES = {
    "chain1_01": "spine_01", "chain1_02": "spine_02", "chain1_04": "neck", "chain2_03": "head",
    "chain3_01": "ear.R", "chain3_02": "ear_02.R",
    **{"hind_stalk_%02d" % number: "tail_%02d" % number for number in range(1, 5)},
    **{"%s_leg_%02d.%s" % (pair, number + 1, side): "%s.%s" % (name, side)
       for side in ("L", "R")
       for pair, names in (("front", ("upper_arm", "forearm")), ("hind", ("thigh", "shin", "hock")))
       for number, name in enumerate(names)},
}
# Bones whose weights go into another before they're removed: the ones too short to turn a part of
# their own, and the left ear's regrown chain, whose skin is mirrored from the right ear's.
JOINS = {"chain1_03": "spine_02", "chain2_01": "neck", "chain2_02": "neck", "chain3_03": "ear_02.R",
         "chain3_04": "ear_02.R", "front_leg_03.L": "front_paw.L", "front_leg_03.R": "front_paw.R",
         "hind_leg_04.L": "hind_paw.L", "hind_leg_04.R": "hind_paw.R",
         **{"front_stalk_%02d" % number: "head" for number in range(1, 5)}}
# The generator's head bone runs sideways to the right ear's root; it points along the head to the
# muzzle's tip instead, so the clips' nods turn the head about its own crosswise axis.
HEAD_TIP = (0.0, -0.64, 0.50)
# The head's skin (in front of this depth and above this height, metres) whose left side takes the
# right side's weights mirrored: the left ear and the head around it.
HEAD = (-0.30, 0.25)
# The foot's skin below this height (metres) is the paw's: the generator gave the heels to the
# hocks (and the backs of the fore feet to the forearms), which then sink into the ground as the
# legs reach for their planted paws. The hind heel reaches higher (HEEL) than the fore foot.
FOOT, HEEL = 0.075, 0.12
# The generator weighted the belly to the legs; the skin this near the midline (metres), or
# between the fore and the hind legs (its depth within BELLY_SPAN), and above the feet moves with the
# trunk bone over it instead (by its depth: TRUNK_BONES, from the front), so a swinging leg doesn't
# drag the belly down into the ground (#1422's trap).
MIDLINE = 0.07
BELLY_SPAN = (-0.12, 0.13)
TRUNK_BONES = ((-0.064, "spine_02"), (0.068, "spine_01"), (math.inf, "hips"))
LEG_BONES = ("upper_arm", "forearm", "front_paw", "thigh", "shin", "hock", "hind_paw")
# The generator's elbows and knees sit where the legs' bones come out too short above them (the
# dimensions check: the forearm 1.10 of the upper arm, the shin 0.79 of the thigh): each joint
# moves to this height (metres), its side and depth kept.
ELBOW, KNEE = 0.222, 0.246
# It nuzzles with its muzzle's tip (its centre of attack).
MUZZLE = (0.0, -0.64, 0.47)

# Its eyes (lib/eyes.py through lib/marked_eyes.py): a dark pupil, a soft violet-blue iris that
# glows a little, a pale eyeball.
EYE_MATERIALS = {"dark": ((0.03, 0.03, 0.06, 1.0), 0.0), "glow": ((0.36, 0.42, 0.95, 1.0), 0.6),
                 "light": ((0.86, 0.88, 0.95, 1.0), 0.0)}

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

# The quadruped's overlap (clips.FOLLOW) for the bones it has (no jaw), its ears' tips trailing
# their roots.
FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith("jaw")}
FOLLOW.update({"ear_02.L": (2.6, 0.35, 0.0, 0.12), "ear_02.R": (2.6, 0.35, 0.0, 0.12)})

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
# Its legs are too short for the library's gaits at the game's speeds: their planted paws would
# have to reach further than the legs do, and the joints snap (the motion check). So it bounces
# along instead (paddle): its paws skim SKIM over the ground at the lowest, never standing on it,
# and paddle in pairs, a trot as it walks (bouncing once a step, rolling from side to side) and a
# bound as it runs (one big bounce a cycle, pitching). Each gait's cycle covers *_TILES; its bounce
# (metres), its legs' swing either way and their fold as they swing forward (radians), and its roll
# or pitch (radians).
WALK_TILES, RUN_TILES = 2 / 3, 1.25
SKIM = 0.04
WALK_BOUNCE, WALK_SWING, WALK_FOLD, WALK_ROLL = 0.03, 0.30, 0.40, 0.05
RUN_BOUNCE, RUN_SWING, RUN_FOLD, RUN_PITCH = 0.10, 0.45, 0.60, 0.10
# How much of the wolf's moves its body and paws make in its attack, its hit and its long attack.
SHARE = 0.35
GAIT = ("WALK_TILES", "SKIM", "WALK_BOUNCE", "WALK_SWING", "WALK_FOLD", "WALK_ROLL", "RUN_TILES", "RUN_BOUNCE",
        "RUN_SWING", "RUN_FOLD", "RUN_PITCH", "SHARE", "STARS")
OUT = tuning.arguments(globals(), GAIT)
if STARS not in STARS_AT:
    sys.exit("STARS is one of " + ", ".join(STARS_AT))
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * WALK_TILES, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * RUN_TILES, FPS)

# How far its belly sinks as it faints (metres), and how far its forepaws reach out then: its legs
# are short under a big body.
BELLY_HEIGHT = 0.12
FAINT_FOREPAWS = 0.15
# How far its head and neck turn in its long attack, a share of the wolf's: its head rears up past
# its brows otherwise (the brow check).
REAR = 0.7
# The lids shut as it sinks into its faint (clips.faint's sinking, from its stagger to lying).
FAINT_LIDS = (19, 32)

# It hovers (the owner, on #1730): every clip but its faint floats it HOVER (metres) over the
# ground, its legs hanging free, and a loop bobs it BOB up and down about once every BOB_FRAMES
# (a whole number of times a loop, so the seam stays exact). Its faint sinks it to the ground.
HOVER = 0.22
BOB, BOB_FRAMES = 0.025, 60

# Asleep it curls up vertically (the owner, on #1730): its back bows, its head tucks down to its
# chest and its tail curls under it toward its head, a round ball floating in the air, its legs
# tucked in (radians about each bone's X; the legs' the left one's, the right
# mirroring it, much as the library's sleeper on its back folds them, clips.on_back). Each breath
# draws the curl a little tighter (CURL_BREATH of it).
CURL = {"hips": -0.5, "spine_01": 0.5, "spine_02": 0.5, "neck": 1.0, "head": 0.8,
        "tail_01": -0.5, "tail_02": -0.5, "tail_03": -0.5, "tail_04": -0.5, "ear.L": 0.6, "ear.R": 0.6}
CURL_BREATH = 0.06
TUCK = {"upper_arm": (-1.0, 0.0, 0.15), "forearm": (2.2, 0.0, 0.0), "front_paw": (-1.0, 0.0, 0.0),
        "thigh": (-0.8, 0.0, 0.0), "shin": (0.0, 0.0, 0.0), "hock": (-0.4, 0.0, 0.0), "hind_paw": (0.3, 0.0, 0.0)}

# Rolling over (RollOver), in its sleep, curled up in the air: how long it takes (frames), how far
# it turns about its length (onto its side), the frames it's turned from and turns back from, and
# the height of the curled body's middle it turns about (metres, from the root). The overlap's
# springs (motion.follow) read a bone turned past half a circle in all as turned the other way
# round, so the roll and the curl down the tail stay short of that together.
ROLL_FRAMES = 64
ROLL_TURN = math.radians(70.0)
ROLL_KEYS = (24, 36)
ROLL_MIDDLE = 0.27


# --- Paint -------------------------------------------------------------------------------------
def smooth_step(value, low, high):
    share = numpy.clip((value - low) / (high - low), 0.0, 1.0)
    return share * share * (3.0 - 2.0 * share)


def kinds(texels, before):
    """Each texel's kind of paint (0 fur, 1 belly, 2 eye) from the generator's colour, settled
    by the most common kind in its CUBE on the body."""
    value = before.mean(axis=1)
    kind = numpy.zeros(len(before), dtype=numpy.int64)
    kind[(value > BELLY_ABOVE) & (value <= WHITE_ABOVE)] = 1
    kind[value < DARK_BELOW] = 2
    # The glints and the painted stars are fur: our eyes have no glint, and our stars replace
    # the painted ones.
    kind[(value > WHITE_ABOVE) | (before[:, 0] > before[:, 2] + YELLOW)] = 0
    kind[(kind == 1) & (texels.normals[:, 2] > BELLY_FACING)] = 0
    cube = numpy.floor((texels.spots - texels.spots.min(axis=0)) / CUBE).astype(numpy.int64)
    span = cube.max(axis=0) + 1
    key = (cube[:, 0] * span[1] + cube[:, 1]) * span[2] + cube[:, 2]
    cubes, where = numpy.unique(key, return_inverse=True)
    counts = numpy.zeros((len(cubes), 3), dtype=numpy.int64)
    numpy.add.at(counts, (where, kind), 1)
    return counts.argmax(axis=1)[where]


def patch(texels):
    """How much of each texel the night sky covers (0..1), where STARS places it."""
    spots, normals = texels.spots, texels.normals
    if STARS == "all":
        return numpy.ones(len(spots))
    trunk = smooth_step(spots[:, 1], *TRUNK[0]) * smooth_step(-spots[:, 1], -TRUNK[1][0], -TRUNK[1][1])
    if STARS == "back":
        return trunk * smooth_step(normals[:, 2], *BACK)
    y, z, length, height = FLANK
    oval = numpy.sqrt(((spots[:, 1] - y) / length) ** 2 + ((spots[:, 2] - z) / height) ** 2)
    return trunk * smooth_step(-oval, -1.0, -1.0 + FLANK_EDGE) * smooth_step(numpy.abs(normals[:, 0]), 0.3, 0.6)


def sky(texels):
    """The night sky's colour at each texel: the panorama around STARS_MIDDLE, looked up by the
    texel's direction from it."""
    panorama = starfield.Sky(SKY_WIDTH, SKY_HEIGHT)
    panorama.background()
    starfield.stars(panorama, SEED, STAR_COUNT, SMALLEST, LARGEST, SPARKLES, RAY, POLAR)
    offset = texels.spots - numpy.array(STARS_MIDDLE)
    lon = numpy.arctan2(offset[:, 0], -offset[:, 1])
    lat = numpy.arctan2(offset[:, 2], numpy.hypot(offset[:, 0], offset[:, 1]))
    column = numpy.clip(((lon + math.pi) / (2.0 * math.pi) * SKY_WIDTH).astype(int), 0, SKY_WIDTH - 1)
    row = numpy.clip(((lat + math.pi / 2.0) / math.pi * SKY_HEIGHT).astype(int), 0, SKY_HEIGHT - 1)
    return numpy.clip(panorama.pixels[row, column], 0.0, 1.0)


def paint(skin, starry=True):
    """The colour and the glow textures, painted from where each texel lies at rest; not `starry`,
    without the night sky."""
    # The generator's one base colour image, which every material shares.
    (old,) = {marked_eyes.image(material) for material in skin.data.materials} - {None}
    width = old.size[0]
    before = numpy.array(old.pixels[:]).reshape(old.size[1], width, 4)[..., :3]
    texels = repaint.Texels(skin.data, TEXTURE)
    # The old atlas is the same size, so a texel's row and column read its old colour.
    kind = kinds(texels, before[texels.rows * width // TEXTURE, texels.columns * width // TEXTURE])
    flat = numpy.array((FUR, BELLY, EYE))[kind]
    night = sky(texels)
    cover = patch(texels) * ((kind != 2) if STARS == "all" else (kind == 0)) * starry
    colour = flat + (night - flat) * cover[:, None]
    glow = night * (SKY_GLOW * cover)[:, None]
    covered = texels.covered()
    canvas = repaint.dilate(texels.paint(texels.canvas(FUR), colour), covered, 4)
    shine = repaint.dilate(texels.paint(texels.canvas((0.0, 0.0, 0.0)), glow), covered, 4)
    step = TEXTURE // GLOW_TEXTURE
    shine = shine.reshape(GLOW_TEXTURE, step, GLOW_TEXTURE, step, 3).mean(axis=(1, 3))
    print("PAINT texels %d, fur %.0f%%, belly %.0f%%, eye %.1f%%, night sky %.0f%% (%s)" % (
        len(kind), 100.0 * (kind == 0).mean(), 100.0 * (kind == 1).mean(), 100.0 * (kind == 2).mean(),
        100.0 * cover.mean(), STARS))
    return repaint.image("nuvvoluvvo", canvas), repaint.image("nuvvoluvvo_glow", shine)


def material(skin, colour, glow):
    """One material: the painted colour, the stars' glow, matte and single-sided."""
    out = bpy.data.materials.new("nuvvoluvvo")
    out.use_backface_culling = True
    nodes, links = out.node_tree.nodes, out.node_tree.links
    shader = nodes["Principled BSDF"]
    for image, socket in ((colour, "Base Color"), (glow, "Emission Color")):
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        links.new(texture.outputs["Color"], shader.inputs[socket])
    shader.inputs["Emission Strength"].default_value = 1.0
    shader.inputs["Roughness"].default_value = 1.0
    shader.inputs["Metallic"].default_value = 0.0
    skin.data.materials.clear()
    skin.data.materials.append(out)


# --- Rig ---------------------------------------------------------------------------------------
# The gaits' leg pairs, by their phase in the cycle: a trot's diagonals, a bound's fore and hind.
TROT = {("front", "L"): 0.0, ("hind", "R"): 0.0, ("front", "R"): 0.5, ("hind", "L"): 0.5}
BOUND = {("front", "L"): 0.0, ("front", "R"): 0.0, ("hind", "L"): 0.5, ("hind", "R"): 0.5}
LEGS = {"front": ("upper_arm", "forearm"), "hind": ("thigh", "shin")}


def paddle(frames, pairs, bounces, bounce, swing, fold, roll=0.0, pitch=0.0):
    """A looping gait of smooth waves, posed on every frame (see WALK_TILES): the body bounces
    `bounces` times a cycle, `bounce` high over its paws' SKIM, rolling by `roll` and pitching by
    `pitch`, the head countering the pitch; each leg swings `swing` either way at its phase in
    `pairs`, folding by `fold` as it swings forward. Its paws never stand on the ground, so they
    can't slide on it."""
    poses = []
    for step in range(frames + 1):
        lap = 2.0 * math.pi * step / frames
        rise = 0.5 - 0.5 * math.cos(bounces * lap)
        nod = pitch * math.sin(lap)
        pose = {"root_loc": (0.0, SKIM + bounce * rise, 0.0), "hips": (nod, roll * math.sin(lap), 0.0),
                "neck": (-0.6 * nod, 0.0, 0.0), "head": (-0.3 * nod, 0.0, 0.0)}
        for (leg, side), phase in pairs.items():
            turn = lap - 2.0 * math.pi * phase
            upper, lower = LEGS[leg]
            # A leg turned about +X swings back, so it swings forward on the way down its sine: the
            # fold, which lifts its paw (about -X), peaks halfway forward, smoothly.
            folded = fold * (0.5 - 0.5 * math.cos(turn)) ** 2
            pose["%s.%s" % (upper, side)] = (swing * math.sin(turn), 0.0, 0.0)
            pose["%s.%s" % (lower, side)] = (-folded, 0.0, 0.0)
        poses.append((step + 1, pose))
    return clips.Clip(poses, loop=True, planted=False)


def mirror_head(skin):
    """The head's left side takes the weights of its right side mirrored (a vertex those of the
    nearest one at its mirrored spot), the right ear's bones as the left ear's: the left ear's own
    chain was regrown into the head by the import."""
    right = [vertex for vertex in skin.data.vertices if vertex.co.x <= 0.0]
    tree = kdtree.KDTree(len(right))
    for number, vertex in enumerate(right):
        tree.insert(vertex.co, number)
    tree.balance()
    groups = {group.index: group.name for group in skin.vertex_groups}
    for side in ("ear.L", "ear_02.L"):
        if skin.vertex_groups.get(side) is None:
            skin.vertex_groups.new(name=side)
    for vertex in skin.data.vertices:
        if vertex.co.x <= 0.0 or vertex.co.y > HEAD[0] or vertex.co.z < HEAD[1]:
            continue
        _spot, number, _distance = tree.find(Vector((-vertex.co.x, vertex.co.y, vertex.co.z)))
        mirrored = [(groups[element.group].replace(".R", ".L"), element.weight)
                    for element in right[number].groups if element.weight > 0.0]
        for element in list(vertex.groups):
            skin.vertex_groups[groups[element.group]].remove([vertex.index])
        for name, weight in mirrored:
            skin.vertex_groups[name].add([vertex.index], weight, "REPLACE")


def rename(rig, skin):
    rigged.rename(rig, skin, {old: new for old, new in RENAMES.items() if old in rig.data.bones})
    rigged.merge(skin, JOINS)
    for bone, paw, height in (("hock", "hind_paw", HEEL), ("forearm", "front_paw", FOOT)):
        rigged.merge(skin, {"%s.%s" % (bone, side): "%s.%s" % (paw, side) for side in ("L", "R")},
                     lambda vertex, height=height: vertex.co.z < height)
    # From the front: each takes what lies in front of its limit and is still the legs'.
    for limit, trunk in TRUNK_BONES:
        rigged.merge(skin, {"%s.%s" % (bone, side): trunk for bone in LEG_BONES for side in ("L", "R")},
                     lambda vertex, limit=limit: vertex.co.z > FOOT and vertex.co.y < limit and (
                         abs(vertex.co.x) < MIDLINE or BELLY_SPAN[0] < vertex.co.y < BELLY_SPAN[1]))
    mirror_head(skin)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    for side in ("L", "R"):
        edit["front_paw." + side].head = edit["front_leg_03." + side].head
        edit["front_paw." + side].parent = edit["forearm." + side]
        edit["hind_paw." + side].parent = edit["hock." + side]
        # The forelegs hang from the withers, not the neck, so the neck bows without dragging
        # the shoulders.
        edit["upper_arm." + side].parent = edit["spine_02"]
        for upper, lower, height in (("upper_arm.", "forearm.", ELBOW), ("thigh.", "shin.", KNEE)):
            joint = edit[upper + side].tail.copy()
            joint.z = height
            edit[upper + side].tail = joint
            edit[lower + side].head = joint
    neck, head = edit["neck"], edit["head"]
    neck.parent = edit["spine_02"]
    neck.tail = head.head
    head.parent = neck
    for child in head.children:
        child.use_connect = False
    head.tail = Vector(HEAD_TIP)
    # The left ear: the right one's bones mirrored.
    for name in ("ear.R", "ear_02.R"):
        bone = edit[name]
        mirror = edit.new(name.replace(".R", ".L"))
        mirror.head = Vector((-bone.head.x, bone.head.y, bone.head.z))
        mirror.tail = Vector((-bone.tail.x, bone.tail.y, bone.tail.z))
    edit["ear_02.R"].tail = edit["chain3_04"].tail
    edit["ear_02.L"].tail = Vector((-edit["ear_02.R"].tail.x, edit["ear_02.R"].tail.y, edit["ear_02.R"].tail.z))
    edit["ear.L"].parent = head
    edit["ear_02.L"].parent = edit["ear.L"]
    for name in JOINS:
        edit.remove(edit[name])
    bpy.ops.object.mode_set(mode="OBJECT")
    for name in JOINS:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    rigged.roll(rig)


# --- Clips -------------------------------------------------------------------------------------
def tucked(pose):
    """`pose` with its legs tucked up (TUCK), the right ones mirroring the left."""
    for bone, (x, y, z) in TUCK.items():
        pose[bone + ".L"] = (x, y, z)
        pose[bone + ".R"] = (x, -y, -z)
    return pose


def curled(chest):
    """Its sleeping pose at `chest` (0..1) of a breath: curled up vertically (CURL), its legs
    tucked in."""
    pose = {bone: ((1.0 + CURL_BREATH * chest) * turn, 0.0, 0.0) for bone, turn in CURL.items()}
    return tucked(pose)


def roll_over():
    """Turning over in its sleep, curled up in the air: it rolls about its length, over and back
    (ROLL_TURN), easing in and out, keyed every other frame along a smootherstep (legs.ease), so
    it never jolts."""
    lying = curled(0.0)

    def pose(share):
        # The root turns about its foot, whose Y points up: the shift keeps the body's middle
        # where it was.
        roll = ROLL_TURN * share
        posed = dict(lying)
        posed["root_loc"] = (ROLL_MIDDLE * math.sin(roll), ROLL_MIDDLE * (1.0 - math.cos(roll)), 0.0)
        posed["root"] = (0.0, 0.0, roll)
        return posed

    over, back = ROLL_KEYS
    keys = []
    for start, end, there in ((1, over, True), (back, ROLL_FRAMES, False)):
        for frame in range(start, end, 2):
            u = legs.ease((frame - start) / (end - start))
            keys.append((frame, pose(u if there else 1.0 - u)))
        keys.append((end, pose(1.0 if there else 0.0)))
    return clips.Clip(keys, planted=False)


def hover(name, poses, loop):
    """An animate overlay (see HOVER): it floats every clip but Faint, which sinks to the ground
    from its float, smoothly, as it falls."""
    last = len(poses) - 1
    bobs = max(1, round(last / BOB_FRAMES))
    for index, (_frame, pose) in enumerate(poses):
        if name == "Faint":
            lift = HOVER * (1.0 - legs.ease(index / last))
        elif loop:
            lift = HOVER + BOB * math.sin(2.0 * math.pi * bobs * index / last)
        else:
            lift = HOVER
        x, y, z = pose.get("root_loc", (0.0, 0.0, 0.0))
        pose["root_loc"] = (x, y + lift, z)


def afloat(made):
    """The clips `made` (name: Clip) with their legs hanging free (no paw stands on the ground)."""
    for clip in made.values():
        clip.planted = False
    return made


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "NuvvoluvvoRig", "Nuvvoluvvo"
    rigged.flatten(rig, skin)
    scene.select_only(skin)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_mesh keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    # It wears the flat paint until our eyes are in: lib/marked_eyes.py finds the eyes by their
    # dark paint, which the night sky would hide. Then the sky goes into the same images.
    night = paint(skin)
    colour, glow = paint(skin, starry=False)
    material(skin, colour, glow)
    rename(rig, skin)
    lids, eye_points = marked_eyes.replace(rig, skin, materials.palette(EYE_MATERIALS), FAINT_LIDS)
    for image, starry in zip((colour, glow), night):
        image.pixels.foreach_set(numpy.array(starry.pixels[:], dtype=numpy.float32))
        image.pack()
        bpy.data.images.remove(starry)
    attachments.add(rig, eye_points, [(MUZZLE, "head")])

    def shut(name, poses, loop):
        # Its eyes stay shut while it rolls over in its sleep, as they do while it sleeps.
        lids.shut("Sleep" if name == "RollOver" else name, poses, loop)

    clips.animate(rig, afloat({
        "Idle": clips.idle(),
        "Walk": paddle(WALK_FRAMES, TROT, 2, WALK_BOUNCE, WALK_SWING, WALK_FOLD, roll=WALK_ROLL),
        "Run": paddle(RUN_FRAMES, BOUND, 1, RUN_BOUNCE, RUN_SWING, RUN_FOLD, pitch=RUN_PITCH),
        "Attack": adopted.lesser(clips.attack(), SHARE, lift=SHARE),
        "Hit": adopted.lesser(clips.hit(), SHARE, lift=SHARE),
        "Faint": adopted.lesser(clips.faint(BELLY_HEIGHT, forepaws=FAINT_FOREPAWS), SHARE, lift=SHARE),
        **{name: adopted.lesser(clip, SHARE, turns=REAR, lift=SHARE) for name, clip in clips.channel().items()},
        "Feed": clips.feed(forepaws=0.04),
        "Sleep": clips.sleep(curled, paws={}, planted=False),
        "RollOver": roll_over(),
    }), SCALE, ground_meshes=[skin], chains=FOLLOW, limbs=adopted.limbs(rig), overlays=[shut, hover])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
