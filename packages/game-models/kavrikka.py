"""The Kavrikka (#1733): the Kalvrakkor's first form, a frost-and-fire pup, magma on its right side
and ice on its left, with one tail. Its mesh and rig come from the owner's generated model
(`sources/kavrikka.glb`, made by import_source.py from the download, sized to a pup: see the
asset's SOURCE.md). Its paint is the Frostfire Hound's, which the Kalvrakkor wears, so the two
read as one line (lib/frostfire.py, as the owner asked: "the same treatment, so its magma flows the
way the hound's does"): the whole right side dark basalt split by glowing cracks, the left side
pale ice with frosted cracks, the border running along the cracks, tail included, and plain pads
under the paws. The generator modelled its eyes as glowing balls of their own; they go, and ours
take their place (lib/marked_eyes.py), the right one amber and the left one pale cyan like the
hound's.

It names the generator's bones to the library's quadruped scheme and animates every creature clip
with the library's clips, its legs planted by lib/adopted.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/kavrikka.py -- packages/game/assets/kavrikka/kavrikka.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py).

Blender is Z-up and it faces -Y (the game's +Z); its left is +X. The source is already at the
game's size, so its metres are the clips' unscaled ones (SCALE 1).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import adopted, attachments, clips, frostfire, marked_eyes, metrics, rigged, scene, tuning  # noqa: E402
from lib.materials import material, palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "kavrikka.glb")
FPS = 30
SCALE = 1.0

# --- The paint ---------------------------------------------------------------------------------
# The hound's paint (lib/frostfire.py) at a pup's size: the midline between its sides is its own
# middle, and its cells and cracks are a little smaller than the hound's, so as many of them
# cross its smaller body; a sole no higher than 4 cm.
LOOK = frostfire.Look("kavrikka", midline=0.0, cell=0.065, seed=1733, crack=0.003, glow_reach=0.005,
                      sole_height=0.04)

# --- Its eyes ----------------------------------------------------------------------------------
# The generator's eyes are glowing balls set in its head, amber and pale cyan; ours take their
# place. Its paint's glowing magma is orange, so only an amber or a cyan glow is an eye's (as the
# hound's own eyes are told from its cracks, marked_eyes.BEASTS).
MARKED = marked_eyes.Marked("AMBER/ICE", marked_eyes.glow((36.0, 50.0), (170.0, 200.0)), mirror=1.0)
# Our eyes' colours: the dark eyeball and pupil, and the glows, the ice side's on the left, the magma side's on the right; the lids and brows take each
# side's colour.
COLORS = {
    "dark": ((0.02, 0.02, 0.03, 1.0), 0.0),
    "glow": (marked_eyes.linear(frostfire.ICE_EYE), 1.0),
    "skin": (marked_eyes.linear(frostfire.ICE[0]), 0.0),
}
RIGHT = {
    "glow": ("glow.R", marked_eyes.linear(frostfire.MAGMA_EYE), 1.0),
    "skin": ("skin.R", marked_eyes.linear(frostfire.BASALT[0]), 0.0),
}
# A pup's eyes: a round pupil and a soft brow.
EYE_SHAPE = {"pupil": (0.35, 0.45), "brow_size": 0.6}
# Ours are this share of the generator's eye balls across (marked_eyes.modelled gives each mark
# its ball's size): as large, they stood out of the head like buttons. They sit this share of
# their width further out than the balls' fronts, clear of the head's skin around the sockets,
# which otherwise crossed the right eye's top (the brow check).
EYE_SHARE, EYE_OUT = 0.7, 0.15
# Faint's frames over which the lids shut (eyes.Lids): as it sinks.
FAINT_LIDS = (14, 34)

# --- The rig -----------------------------------------------------------------------------------
# The generator's bones (import_source.py named them) to the library's quadruped scheme the clips
# key. Weights first go from the bones that go to the ones that stay (MERGES): the two stubs
# zigzagging under the chest into the chest, the nape into the neck, the snout's, jaw's and
# eyes' chains into the head (it doesn't open its mouth, as the hound doesn't), and each paw's
# toe bones into the bone above them, so the paw the clips plant is the whole foot, on both
# sides alike (the generator gave its right forepaw one bone more).
MERGES = {
    "chain1_02": "chain1_01", "chain1_03": "chain1_01", "chain2_02": "chain2_01",
    **{name: "chain2_03" for name in ("front_stalk_01", "front_stalk_02", "front_stalk_01.R", "front_stalk_02.R",
                                      "mid_stalk_01", "mid_stalk_02")},
    "front_paw.L": "front_leg_03.L", "front_leg_04.R": "front_leg_03.R", "front_paw.R": "front_leg_03.R",
    "hind_paw.L": "hind_leg_04.L", "hind_paw.R": "hind_leg_04.R",
}
RENAMES = {
    "chain1_01": "spine_02", "chain2_01": "neck", "chain2_03": "head",
    "stalk_01.L": "ear.L", "stalk_02.L": "ear_tip.L", "hind_stalk_01.R": "ear.R", "hind_stalk_02.R": "ear_tip.R",
    **{"hind_stalk_%02d" % number: "tail_%02d" % number for number in range(1, 6)},
    **{"%s_leg_%02d.%s" % (pair, number + 1, side): "%s.%s" % (name, side)
       for side in ("L", "R")
       for pair, names in (("front", ("upper_arm", "forearm", "front_paw")),
                           ("hind", ("thigh", "shin", "hock", "hind_paw")))
       for number, name in enumerate(names)},
}
# The heel's skin below this height (metres) goes from the hock to the hind paw, so the whole sole
# is the paw's and stays where the paw is planted as the hock turns.
HEEL = 0.06
# The legs' tops hold much of the trunk's skin: above this height (metres), and nearer the midline
# than this (the belly between the legs), the shoulders' and the haunches' skin goes to the chest
# and the back, so a swinging leg doesn't drag the trunk thin (the volume check), as Fohossa's
# legs give theirs up.
TRUNK, BELLY = 0.24, 0.045
# The brisket, the upper arms' skin ahead of this depth (metres along Y, the shoulder joint's a
# little behind it), goes to the chest too, so the neck's base keeps its width as a foreleg steps
# out (as quadruped.bind_underside's `brisket`).
BRISKET = -0.2
# The tip of its nose: the head bone points along the head to it (the generator's runs sideways to
# the left eye), so the clips' nods turn the head about its own crosswise axis; it bites with it.
NOSE = (0.0, -0.45, 0.45)

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith(("ear.", "jaw"))}
FOLLOW.update({"tail_05": (1.9, 0.4, 0.0, 0.15)})

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s. A pup's legs are short, so it takes shorter strides
# than the hound.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_TILES, RUN_TILES = 0.35, 0.9
WALK_DUTY, WALK_LIFT, WALK_CURL, WALK_ROLL, WALK_BOB = 0.4, 0.15, 0.4, 0.05, 0.4
RUN_DUTY, RUN_FOLD, RUN_SPINE_FLEX, RUN_ROLL, RUN_BOB = 0.3, 0.5, 0.06, 0.0, 0.4
GAIT = ("WALK_TILES", "WALK_DUTY", "WALK_LIFT", "WALK_CURL", "WALK_ROLL", "WALK_BOB", "RUN_TILES", "RUN_DUTY",
        "RUN_FOLD", "RUN_SPINE_FLEX", "RUN_ROLL", "RUN_BOB")
OUT = tuning.arguments(globals(), GAIT)
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * WALK_TILES, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * RUN_TILES, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

# How far its belly lies above the ground, and how much of the wolf's reach its clips keep
# (adopted.lesser): its legs are shorter than the hound's.
BELLY_HEIGHT = 0.20
SHARE = 0.35
FAINT_FOREPAWS = 0.17
SLEEP_PAWS = {"front_paw": (0.0, 0.0, 0.17), "hind_paw": (0.05, 0.0, -0.05)}


def rename(rig, skin):
    rigged.merge(skin, MERGES)
    rigged.merge(skin, {"front_leg_01.L": "chain1_01", "front_leg_01.R": "chain1_01",
                        "hind_leg_01.L": "spine_01", "hind_leg_01.R": "spine_01"},
                 lambda vertex: vertex.co.z > TRUNK or abs(vertex.co.x) < BELLY)
    rigged.merge(skin, {"front_leg_01.L": "chain1_01", "front_leg_01.R": "chain1_01"},
                 lambda vertex: vertex.co.y < BRISKET)
    rigged.merge(skin, {"hind_leg_03.L": "hind_leg_04.L", "hind_leg_03.R": "hind_leg_04.R"},
                 lambda vertex: vertex.co.z < HEEL)
    for name in MERGES:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    # Each foot's toe bones go into the bone above them, which reaches to the toe's tip.
    for keep, toes in (("front_leg_03.L", ("front_paw.L",)), ("front_leg_03.R", ("front_leg_04.R", "front_paw.R")),
                       ("hind_leg_04.L", ("hind_paw.L",)), ("hind_leg_04.R", ("hind_paw.R",))):
        edit[keep].tail = edit[toes[-1]].tail
        for toe in toes:
            edit.remove(edit[toe])
    chest, neck, head = edit["chain1_01"], edit["chain2_01"], edit["chain2_03"]
    for side in ("L", "R"):
        edit["front_leg_01." + side].parent = chest
    neck.parent = chest
    neck.tail = head.head
    head.parent = neck
    head.use_connect = False
    for name in ("chain1_02", "chain1_03", "chain2_02", "front_stalk_01", "front_stalk_02", "front_stalk_01.R",
                 "front_stalk_02.R", "mid_stalk_01", "mid_stalk_02"):
        for child in edit[name].children:
            if child.name not in MERGES:
                child.parent = head if name.startswith(("front_", "mid_")) else chest
        edit.remove(edit[name])
    for child in head.children:
        child.use_connect = False
    head.tail = Vector(NOSE)
    bpy.ops.object.mode_set(mode="OBJECT")
    rigged.rename(rig, skin, RENAMES)
    rigged.roll(rig)


def eyes(rig, skin, marks):
    """Ours where the generator's were (`marks`), their glow and lids each side's colour: the
    right eye's glow and its lid and brow take the magma side's (RIGHT), once joined into the skin."""
    lids, spots = marked_eyes.replace(rig, skin, palette(COLORS), FAINT_LIDS, marks=marks, **EYE_SHAPE)
    slots = {mat.name: index for index, mat in enumerate(skin.data.materials)}
    for key, (name, colour, glow) in RIGHT.items():
        skin.data.materials.append(material(name, colour, glow))
        right = len(skin.data.materials) - 1
        for polygon in skin.data.polygons:
            if polygon.material_index == slots[key] and polygon.center.x < 0.0:
                polygon.material_index = right
    return lids, spots


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "KavrikkaRig", "Kavrikka"
    rigged.flatten(rig, skin)
    scene.select_only(skin)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    rename(rig, skin)
    # The generator's glowing eyes, found on its paint, then taken out of the mesh.
    marks = marked_eyes.find(marked_eyes.Head(skin, "head"), MARKED)
    marked_eyes.modelled(skin, marks)
    for mark in marks:
        mark.width, mark.height = mark.width * EYE_SHARE, mark.height * EYE_SHARE
        mark.middle = mark.middle + mark.normal * mark.width * EYE_OUT
    colour, glow = frostfire.paint(skin, {polygon.index: "body" for polygon in skin.data.polygons}, LOOK)
    frostfire.material(skin, "kavrikka", colour, glow)
    lids, spots = eyes(rig, skin, marks)
    attachments.add(rig, spots, [(NOSE, "head")])
    body = adopted.Body(rig, NOSE)
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, body, clips.WALK, duty=WALK_DUTY, fold=0.0, lift=WALK_LIFT,
                           curl=WALK_CURL, roll=WALK_ROLL, bob=WALK_BOB),
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, body, clips.GALLOP, duty=RUN_DUTY, fold=RUN_FOLD,
                          spine_flex=RUN_SPINE_FLEX, roll=RUN_ROLL, bob=RUN_BOB, planted=False),
        "Attack": adopted.lesser(clips.attack(), SHARE),
        "Hit": adopted.lesser(clips.hit(), SHARE),
        "Faint": adopted.lesser(clips.faint(BELLY_HEIGHT, forepaws=FAINT_FOREPAWS), SHARE),
        **{name: adopted.lesser(clip, SHARE) for name, clip in clips.channel().items()},
        "Feed": clips.feed(forepaws=0.03),
        "Sleep": clips.sleep(clips.curled(BELLY_HEIGHT), SLEEP_PAWS),
    }, SCALE, ground_meshes=[skin], chains=FOLLOW, limbs=adopted.limbs(rig), overlays=[lids.shut])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
