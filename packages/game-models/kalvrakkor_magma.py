"""The Korvakkar (#1771), the Kalvrakkor's magma form: its fire side has taken over the whole hound,
lean and fox-like on black basalt cracked with magma, with nine tails of flowing magma fanned out
behind it, each tipped with an ember crystal. Its mesh, paint and body's rig come from the owner's
generated model (`sources/kalvrakkor_magma.glb`, made by import_source.py from the download, sized
to its hex as a stronger monster: see the asset's SOURCE.md). The generator's two black ovals become
our eyes (lib/marked_eyes.py).

The generator's rig holds nine tails on two chains (the owner: "only two are rigged"), so every tail
gets a chain of its own from the mesh (lib/tails.py), which moves in every clip. It names the
generator's bones to the library's quadruped scheme, adds the ears a bone each, and animates every
creature clip with the library's clips, its legs planted by lib/adopted.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/kalvrakkor_magma.py -- packages/game/assets/kalvrakkor_magma/kalvrakkor_magma.glb

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
from lib.materials import palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "kalvrakkor_magma.glb")
FPS = 30
SCALE = 1.0

# --- Its eyes ----------------------------------------------------------------------------------
# Ours where the generator's black ovals are: a dark eyeball, a glow of the line's magma eye; the lids
# and brows take the skin's colour around the marks.
COLORS = {
    "dark": ((0.02, 0.02, 0.03, 1.0), 0.0),
    "glow": (marked_eyes.linear(frostfire.MAGMA_EYE), 1.0),
}
# The marks are black on a head of dark basalt, off the middle (marked_eyes.BEASTS).
MARKED = marked_eyes.BEASTS["assets/kalvrakkor_magma/kalvrakkor_magma.glb"]
# Faint's frames over which the lids shut (eyes.Lids): as it sinks.
FAINT_LIDS = (14, 34)

# --- The rig -----------------------------------------------------------------------------------
# The generator's bones (import_source.py named them) to the library's quadruped scheme the clips
# key. Weights first go from the bones that go to the ones that stay (MERGES): the pelvis' zigzag of
# three short bones into the hips, the chest's stub into the chest, the skull's top into the head,
# and each paw's toe bones into the bone above them, so the paw the clips plant is the whole foot.
MERGES = {
    "chain1_02": "chain1_01", "chain2_01": "hips", "chain2_02": "hips", "chain3_01": "hips", "stalk_03": "stalk_02",
    "1_leg_04": "1_leg_03", "1_paw": "1_leg_03", "2_leg_04": "2_leg_03", "2_paw": "2_leg_03",
    "3_paw": "3_leg_04", "4_paw": "4_leg_04",
}
RENAMES = {
    "chain1_01": "spine_02", "stalk_01": "neck", "stalk_02": "head",
    **{"%d_leg_%02d" % (number, index + 1): "%s.%s" % (name, side)
       for number, side, names in ((1, "L", ("upper_arm", "forearm", "front_paw")),
                                   (2, "R", ("upper_arm", "forearm", "front_paw")),
                                   (3, "L", ("thigh", "shin", "hock", "hind_paw")),
                                   (4, "R", ("thigh", "shin", "hock", "hind_paw")))
       for index, name in enumerate(names)},
}
# The legs' tops hold much of the trunk's skin: above this height (metres) the shoulders' and the
# haunches' skin goes to the chest and the hips, so a swinging leg doesn't drag the trunk thin (the
# volume check), as Fohossa's legs give theirs up.
TRUNK = 0.31
# The heel's skin below this height (metres) goes from the hock to the hind paw, so the whole sole
# is the paw's and stays where the paw is planted as the hock turns.
HEEL = 0.06
# The tip of its nose: the head bone points along the head to it, so the clips' nods turn the head
# about its own crosswise axis; it bites with it.
NOSE = (0.014, -0.547, 0.625)
# Its ears, a bone each, the generator having none: (its base, its tip). A vertex is an ear's when
# it lies along that line, nearer it than EAR_REACH and off the head's middle by EAR_OFF.
MIDDLE = 0.014
EARS = {"L": ((0.062, -0.33, 0.675), (0.082, -0.341, 0.807)), "R": ((-0.034, -0.33, 0.675), (-0.055, -0.341, 0.807))}
EAR_REACH, EAR_OFF = 0.062, 0.022
# The skin comes off the head over this share of the ear from its base.
EAR_BLEND = 0.3

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {}

FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith(("jaw", "tail_"))}

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_TILES, RUN_TILES = 0.35, 1.0
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
# (adopted.lesser): a lean body on legs a little shorter than the wolf's.
BELLY_HEIGHT = 0.27
SHARE = 0.22
FAINT_FOREPAWS = 0.2
SLEEP_PAWS = {"front_paw": (0.0, 0.0, 0.2), "hind_paw": (0.06, 0.0, -0.06)}


def rename(rig, skin):
    rigged.merge(skin, MERGES)
    rigged.merge(skin, {"1_leg_01": "chain1_01", "2_leg_01": "chain1_01", "3_leg_01": "hips", "4_leg_01": "hips"},
                 lambda vertex: vertex.co.z > TRUNK)
    rigged.merge(skin, {"3_leg_03": "3_leg_04", "4_leg_03": "4_leg_04"}, lambda vertex: vertex.co.z < HEEL)
    for name in MERGES:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    # Each foot's toe bones go into the bone above them, which reaches to the toe's tip.
    for keep, toes in (("1_leg_03", ("1_leg_04", "1_paw")), ("2_leg_03", ("2_leg_04", "2_paw")),
                       ("3_leg_04", ("3_paw",)), ("4_leg_04", ("4_paw",))):
        edit[keep].tail = edit[toes[-1]].tail
        for toe in toes:
            edit.remove(edit[toe])
    hips, chest, neck, head = edit["hips"], edit["chain1_01"], edit["stalk_01"], edit["stalk_02"]
    # Everything behind the middle hangs from the hips, not from a spine bone, so the spine bends
    # without moving the hind legs' tops.
    for name in ("3_leg_01", "4_leg_01", "stalk_01.L", "stalk_01.R"):
        edit[name].use_connect = False
        edit[name].parent = hips
    for name in ("chain3_01", "chain2_02", "chain2_01"):
        edit.remove(edit[name])
    chest.tail = neck.head
    for side in ("1", "2"):
        edit[side + "_leg_01"].use_connect = False
        edit[side + "_leg_01"].parent = chest
    neck.use_connect = False
    neck.parent = chest
    edit.remove(edit["chain1_02"])
    edit.remove(edit["stalk_03"])
    head.tail = Vector(NOSE)
    bpy.ops.object.mode_set(mode="OBJECT")
    rigged.rename(rig, skin, RENAMES)
    rigged.roll(rig)


def ears(rig, skin):
    """A bone for each ear, hung from the head, holding the skin along it."""
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for side, (base, tip) in EARS.items():
        bone = rig.data.edit_bones.new("ear." + side)
        bone.head, bone.tail = Vector(base), Vector(tip)
        bone.parent = rig.data.edit_bones["head"]
        bone.align_roll(Vector((0.0, -1.0, 0.0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    head = skin.vertex_groups["head"]
    for side, (base, tip) in EARS.items():
        group = skin.vertex_groups.new(name="ear." + side)
        start, along = Vector(base), Vector(tip) - Vector(base)
        for vertex in skin.data.vertices:
            if (vertex.co.x - MIDDLE) * (base[0] - MIDDLE) <= 0.0 or abs(vertex.co.x - MIDDLE) < EAR_OFF:
                continue
            share = (vertex.co - start).dot(along) / along.length_squared
            if share <= 0.0 or (vertex.co - start - along * share).length > EAR_REACH:
                continue
            held = min(1.0, share / EAR_BLEND)
            head.add([vertex.index], 1.0 - held, "REPLACE")
            group.add([vertex.index], held, "REPLACE")


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "KalvrakkorMagmaRig", "KalvrakkorMagma"
    rigged.flatten(rig, skin)
    scene.select_only(skin)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    rename(rig, skin)
    ears(rig, skin)
    lids, spots = marked_eyes.replace(rig, skin, palette(COLORS), FAINT_LIDS, marked=MARKED)
    attachments.add(rig, spots, [(NOSE, "head")])
    body = adopted.Body(rig, NOSE)
    chains = {**FOLLOW, **adopted.follow(rig)}
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
        "Feed": clips.feed(forepaws=0.04),
        "Sleep": clips.sleep(clips.curled(BELLY_HEIGHT), SLEEP_PAWS),
    }, SCALE, ground_meshes=[skin], chains=chains, limbs=adopted.limbs(rig), overlays=[lids.shut])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
