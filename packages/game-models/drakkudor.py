"""Drakkudor, the ribwalker (#1476): the hollow ribcage of a long-dead giant, walked by the knotted
heart of dark red muscle that grew inside it, on six legs of bone, a cracked bone plate for a face
with glowing amber eyes and a short bone tail. Its mesh and colour come from a generated model
(`sources/drakkudor.glb`, made by import_source.py from the owner's download: see the asset's
SOURCE.md); this script places it on its feet, rigs it as a hexapod (lib/hexapod.py) and animates
every creature clip.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/drakkudor.py -- packages/game/assets/drakkudor/drakkudor.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes.

Blender is Z-up and it faces -Y (the game's +Z). Sizes are in the source's units, placed by
OFFSET and grown by SCALE at the end.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import attachments, clips, hexapod, legs, metrics, scene  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "drakkudor.glb")
FPS = 30
# A titan: it stands taller than the mana wolf and about twice its length. Its legs stand nearly
# straight, so they only reach so far: at the game's speeds a smaller body would scurry.
SCALE = 2.0
# Moves the source onto its feet: its soles on the ground, the origin midway between its front
# and hind feet.
OFFSET = (0.0, 0.125, 0.566)


def placed(point):
    return tuple(value + shift for value, shift in zip(point, OFFSET))


# Its joints, in the source's units (the left side; the right mirrors it), read off the mesh: the
# spine runs through the vertebrae along its back from the hips to the chest, the neck down to the
# face plate; each leg is a rib's lower end, bending out at the knee.
RIBWALKER = hexapod.Proportions(
    tail=[placed(point) for point in ((0.0, 0.90, 0.085), (0.0, 0.78, 0.10), (0.0, 0.65, 0.135), (0.0, 0.50, 0.19))],
    hips=placed((0.0, 0.35, 0.25)),
    waist=placed((0.0, -0.05, 0.38)),
    chest=placed((0.0, -0.45, 0.42)),
    head_base=placed((0.0, -0.66, 0.28)),
    nose=placed((0.0, -0.95, 0.13)),
    legs={
        "front": [placed(point) for point in ((0.26, -0.51, 0.04), (0.385, -0.56, -0.19), (0.39, -0.63, -0.45),
                                              (0.345, -0.64, -0.566))],
        "mid": [placed(point) for point in ((0.29, -0.125, 0.02), (0.435, -0.12, -0.23), (0.44, -0.14, -0.45),
                                            (0.405, -0.15, -0.566))],
        "hind": [placed(point) for point in ((0.20, 0.31, 0.03), (0.31, 0.355, -0.23), (0.32, 0.385, -0.45),
                                             (0.30, 0.396, -0.566))],
    },
)

# The amber eyes painted on its face plate, looking ahead and a little out.
EYE, EYE_LOOK = placed((0.10, -0.925, 0.095)), (0.2, -1.0, 0.0)
# It rams with its face plate.
RAM = placed((0.0, -0.95, 0.15))

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

# How far it stands lower than its rest pose in every clip (hexapod.crouch), its legs bent a
# little further.
CROUCH = 0.1
# How much further its faint and its sleep lower it, onto its rib tips.
BELLY_HEIGHT = 0.30

# The game's speeds at the model's size (metres a second): a wild monster glides a tile (sqrt(3)
# apart) in 0.8 s, a companion follows at a tile every 0.3 s. Its walk is a wave up each side,
# a tile a cycle, each paw down two fifths of it, so its legs swing as slowly as they can reach.
# Its run is a tripod too fast for planted paws (hexapod.scurry), its paws skimming the ground, a
# cycle as long as the game takes to carry it a tile and a half.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * 1.5, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
# How far (radians) its legs swing either way in its run and lift as they swing forward, and how
# high (unscaled metres) its paws skim the ground.
RUN_SWING, RUN_LIFT, RUN_SKIM = 0.35, 0.3, 0.035

# Where its paws stand braced for its long attack, and where they lie once it has fainted or
# sleeps (the left one's shift from rest; the right mirrors it).
BRACE = {"front": (0.04, 0.0, 0.14), "hind": (0.03, 0.0, -0.08)}
SPLAYED = {"front": (0.08, 0.0, 0.06), "mid": (0.12, 0.0, 0.0), "hind": (0.08, 0.0, -0.06)}


def points(rig):
    """The attachment points (#1007): its two eyes and its face plate, which it rams with."""
    eyes = {side: (spot, "head", look) for side, spot, look in
            (("L", EYE, EYE_LOOK), ("R", (-EYE[0], EYE[1], EYE[2]), (-EYE_LOOK[0], EYE_LOOK[1], EYE_LOOK[2])))}
    attachments.add(rig, eyes, [(RAM, "head")])


def ram():
    """Its attack: it rears back on its hind legs' side, its face plate lowered, still drawing
    back as it holds, then lunges forward and rams with the plate, its front and middle paws
    stepping out after it, rocks back past where it stood and settles."""
    rear = {"root_loc": (0, -0.04, -0.10), "hips": (-0.08, 0, 0), "spine_02": (-0.04, 0, 0), "neck": (0.25, 0, 0),
            "head": (0.12, 0, 0), "tail_01": (-0.2, 0, 0)}
    coiled = dict(rear, root_loc=(0, -0.05, -0.12), neck=(0.3, 0, 0))
    lunge = {"root_loc": (0, 0.02, 0.15), "hips": (0.06, 0, 0), "spine_02": (0.05, 0, 0), "neck": (0.1, 0, 0),
             "head": (-0.15, 0, 0), "tail_01": (0.25, 0, 0)}
    rammed = dict(lunge, root_loc=(0, 0.0, 0.17), head=(0.12, 0, 0), neck=(0.18, 0, 0))
    back = {"root_loc": (0, 0.0, 0.05), "neck": (-0.05, 0, 0), "head": (-0.06, 0, 0), "tail_01": (0.08, 0, 0)}
    past = {"root_loc": (0, -0.01, -0.025), "neck": (0.04, 0, 0), "head": (0.02, 0, 0), "tail_01": (-0.05, 0, 0)}
    steps = []
    for pair, reach, late in (("front", 0.18, 0), ("mid", 0.12, 2)):
        for side, after in (("L", 0), ("R", 1)):
            paw = hexapod.bone(pair, "paw", side)
            steps.append(legs.Step(paw, 9 + late + after, 18 + late + after, (0.0, 0.0, reach), 0.1))
            steps.append(legs.Step(paw, 21 + late + after, 31 + late + after, (0.0, 0.0, 0.0), 0.06))
    return clips.Clip([(1, {}), (8, rear), (11, coiled), (17, lunge), (20, rammed), (26, back),
                       (30, past), (36, {})], steps=steps)


def channel():
    """Its long attack (#1158): the library's braced lunge, its front and hind paws bracing
    (the middle ones stay where they stand), its body moving a little less than a wolf's."""
    channel = clips.channel(brace=hexapod.paws(BRACE))
    for clip in channel.values():
        hexapod.softened(clip, 0.6)
    return channel


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    skin.name = "Drakkudor"
    scene.select_only(skin)
    skin.location = OFFSET
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_faces keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    rig = hexapod.armature("DrakkudorRig", RIBWALKER)
    points(rig)
    scene.apply_scale([rig, skin], SCALE)
    hexapod.bind(skin, rig, SCALE)
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": hexapod.gait(WALK_FRAMES, WALK_STRIDE, RIBWALKER, hexapod.WAVE, duty=0.4, lift=0.1),
        # Its legs hang from a body raised back out of its crouch, its paws skimming the ground.
        "Run": hexapod.scurry(RUN_FRAMES, hexapod.TRIPOD, RUN_SWING, RUN_LIFT, CROUCH + RUN_SKIM),
        "Attack": ram(),
        "Hit": hexapod.softened(clips.hit(), 0.5),
        "Faint": hexapod.faint(BELLY_HEIGHT, SPLAYED),
        **channel(),
        "Feed": clips.feed(neck=0.45, head=0.1, crouch=0.08, forepaws=0.04),
        "Sleep": clips.sleep(hexapod.sleeping(BELLY_HEIGHT), hexapod.paws(SPLAYED)),
    }, SCALE, ground_meshes=[skin], chains=hexapod.FOLLOW, limbs=hexapod.limbs(RIBWALKER),
        overlays=[hexapod.crouch(CROUCH)])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(sys.argv[sys.argv.index("--") + 1])
