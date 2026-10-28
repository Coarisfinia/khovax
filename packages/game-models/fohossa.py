"""Fohossa, the fogbank (#1619): the dream realm's miniboss, a four-legged beast of solid, rounded fog
billows with antler-like horns and lantern eyes. Its mesh, colour and rig come from the owner's
generated model (`sources/fohossa.glb`, made by import_source.py from the download, its rig
adopted by lib/rigged.py and fitted to its hex as a large monster: see the asset's SOURCE.md);
this script names the adopted bones to the library's quadruped scheme and animates every creature
clip with the library's clips, its many-bone legs planted by lib/adopted.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/fohossa.py -- packages/game/assets/fohossa/fohossa.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py).

Blender is Z-up and it faces -Y (the game's +Z). The source is already at the game's size, so its
metres are the clips' unscaled ones (SCALE 1).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import adopted, attachments, clips, metrics, rigged, scene, tuning  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "fohossa.glb")
FPS = 30
SCALE = 1.0

# The adopted rig's names (lib/rigged.py) to the library's quadruped scheme the clips key: the
# trunk's second bone runs back from the hips to the tail's root (the pelvis, where the hind legs
# hang); the spine runs forward from the middle of the back up to the withers, then the neck (whose
# weights hold the throat and the nape) and the head. The generator's short bone under the skull,
# which weighs almost nothing, goes into the neck, so the head hangs from the neck as the clips
# expect. The forelegs hang from the withers rather than the neck, so the neck bows without
# dragging the shoulders. The
# muzzle hangs from the head (a closed mouth with no jaw to open), and the antlers stay as stiff as
# the head they grow from. Each foreleg is a shoulder blade, an upper arm, a forearm, a cannon and
# the hoof, each hind leg a thigh, a shin, a hock and the hoof: the quadruped's joints, which its
# free-swinging gallop turns and the dimensions check measures.
RENAMES = {
    "spine_01": "pelvis",
    "chain1_01": "spine_01", "chain1_02": "spine_02", "chain1_03": "spine_03", "chain1_04": "neck",
    "chain2_01": "skull_base", "chain2_02": "head", "chain3_01": "muzzle_01", "chain3_02": "muzzle_02",
    "stalk_01.L": "antler_01.L", "stalk_02.L": "antler_02.L", "stalk_01.R": "antler_01.R",
    "stalk_02.R": "antler_02.R",
    **{"stalk_%02d" % number: "tail_%02d" % number for number in range(1, 7)},
    **{"%s_leg_%02d.%s" % (pair, number + 1, side): "%s.%s" % (name, side)
       for side in ("L", "R")
       for pair, names in (("front", ("scapula", "upper_arm", "forearm", "cannon")), ("hind", ("thigh", "shin", "hock")))
       for number, name in enumerate(names)},
}
# The generator's head bone runs sideways to the left antler's root; it points along the head to
# the muzzle's tip instead, so the clips' nods turn the head about its own crosswise axis.
HEAD_TIP = (0.0, -0.80, 0.90)

# Its lantern eyes, painted on the colour, looking ahead and a little out; it butts with its muzzle.
EYE, EYE_LOOK = (0.079, -0.713, 0.815), (0.25, -1.0, 0.0)
MUZZLE = (0.0, -0.80, 0.71)

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

# The quadruped's overlap (clips.FOLLOW) for the bones it has, its six-bone tail each looser than
# the one before.
FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith(("ear.", "jaw"))}
FOLLOW.update({"tail_05": (1.9, 0.4, 0.0, 0.15), "tail_06": (1.7, 0.4, 0.0, 0.15)})

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s. It walks four beats on planted paws and gallops on
# free-swinging legs, as the wolf does: at a run's speed, legs reaching for planted paws turn their
# joints too sharply from one frame to the next (#1073).
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_TILES, RUN_TILES = 2 / 3, 1.25
# Each gait's shape (clips.gait): the share of the cycle a paw is down, how far (radians) a leg's
# joints fold as it swings, how high a paw lifts (a share of its leg's reach), how far its toes tip
# down, how far (radians) the body rolls and the spine flexes, and how much of a straight leg's
# sink the body bobs by.
WALK_DUTY, WALK_LIFT, WALK_CURL, WALK_ROLL, WALK_BOB = 0.4, 0.2, 0.4, 0.05, 0.4
RUN_DUTY, RUN_FOLD, RUN_SPINE_FLEX, RUN_ROLL, RUN_BOB = 0.3, 0.5, 0.06, 0.0, 0.4
GAIT = ("WALK_TILES", "WALK_DUTY", "WALK_LIFT", "WALK_CURL", "WALK_ROLL", "WALK_BOB", "RUN_TILES", "RUN_DUTY",
        "RUN_FOLD", "RUN_SPINE_FLEX", "RUN_ROLL", "RUN_BOB")
OUT = tuning.arguments(globals(), GAIT)
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * WALK_TILES, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * RUN_TILES, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

# How far its belly sinks as it faints or sleeps (metres), and where its paws go then and while
# its long attack braces (the left one's shift from rest; the right mirrors it): its legs are
# shorter than a wolf's against its body, so they reach less far.
BELLY_HEIGHT = 0.40
# How much of the wolf's moves its body and paws make in its attack, its hit and its long attack.
SHARE = 0.4
FAINT_FOREPAWS = 0.25
SLEEP_PAWS = {"front_paw": (0.0, 0.0, 0.25), "hind_paw": (0.08, 0.0, -0.08)}


class Body:
    """What clips.gait reads of a quadruped.Proportions, from the adopted rig: each leg's top and
    paw tip, the hips, the shoulders and the muzzle's tip."""

    def __init__(self, rig):
        bones = rig.data.bones
        self.front_leg = [tuple(bones["scapula.L"].head_local), tuple(bones["front_paw.L"].tail_local)]
        self.hind_leg = [tuple(bones["thigh.L"].head_local), tuple(bones["hind_paw.L"].tail_local)]
        self.hips = tuple(bones["hips"].head_local)
        self.chest = tuple(bones["neck"].head_local)
        self.nose = MUZZLE


# The share of the neck's bow the withers take: one joint turning the whole bow pinches the neck
# between the shoulders, whose skin stays (the volume check).
WITHERS = 0.4


def withers(_name, poses, _loop):
    """An animate overlay: the withers (spine_03) take WITHERS of the neck's bow (its turn about X)."""
    for _frame, pose in poses:
        bow = pose.get("neck", (0.0, 0.0, 0.0))
        spine = pose.get("spine_03", (0.0, 0.0, 0.0))
        pose["spine_03"] = (spine[0] + WITHERS * bow[0], spine[1], spine[2])
        pose["neck"] = ((1.0 - WITHERS) * bow[0], bow[1], bow[2])


def lesser(clip, share=SHARE):
    """`clip` with its body's shifts, its paws' moves and its tail's swing `share` as large: its
    legs are short against its body, so they reach less far than the wolf's the library's clips
    were made for, and its long tail would sweep out of its hex."""
    keys = []
    for key in clip.keys:
        pose = {name: tuple(share * value for value in values)
                if name == "root_loc" or name.startswith(("plant.", "tail_")) else values
                for name, values in key[1].items()}
        keys.append((key[0], pose, *key[2:]))
    clip.keys = keys
    for step in clip.steps:
        step.spot = tuple(share * value for value in step.spot)
    return clip


# The skin between the legs, this near the midline (metres), moves with the trunk rather than the
# legs, so a swinging leg doesn't drag the chest's or the belly's underside along (#1422's trap).
MIDLINE = 0.1
# The trunk bone each leg's top hangs from, which takes the weights it gives up there.
TRUNK = {"scapula": "spine_03", "upper_arm": "spine_03", "thigh": "pelvis", "shin": "pelvis"}


def merge(skin, weights, where=lambda vertex: True):
    """Moves the weights of the vertices `where` holds as {from bone: to bone} says."""
    groups = {group.index: group.name for group in skin.vertex_groups}
    moves = [(vertex.index, groups[element.group], element.weight)
             for vertex in skin.data.vertices if where(vertex)
             for element in vertex.groups if groups[element.group] in weights and element.weight > 0.0]
    for index, name, weight in moves:
        skin.vertex_groups[name].remove([index])
        skin.vertex_groups[weights[name]].add([index], weight, "ADD")


def keep_trunk(skin):
    """The legs' tops give up their weights near the midline to the trunk (MIDLINE, TRUNK)."""
    merge(skin, {"%s.%s" % (bone, side): trunk for bone, trunk in TRUNK.items() for side in ("L", "R")},
          lambda vertex: abs(vertex.co.x) < MIDLINE)


def rename(rig, skin):
    rigged.rename(rig, skin, {old: new for old, new in RENAMES.items() if old in rig.data.bones})
    merge(skin, {"skull_base": "neck"})
    skin.vertex_groups.remove(skin.vertex_groups["skull_base"])
    keep_trunk(skin)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    edit["head"].parent = edit["neck"]
    edit.remove(edit["skull_base"])
    for side in ("L", "R"):
        rig.data.edit_bones["scapula." + side].parent = rig.data.edit_bones["spine_03"]
    head = rig.data.edit_bones["head"]
    for child in head.children:
        child.use_connect = False
    head.tail = Vector(HEAD_TIP)
    bpy.ops.object.mode_set(mode="OBJECT")
    # The import turns the bones as glTF's joints lie; the clips turn them about the library's axes.
    rigged.roll(rig)


def points(rig):
    """The attachment points (#1007): its two lantern eyes and its muzzle, which it butts with."""
    eyes = {side: (spot, "head", look) for side, spot, look in
            (("L", EYE, EYE_LOOK), ("R", (-EYE[0], EYE[1], EYE[2]), (-EYE_LOOK[0], EYE_LOOK[1], EYE_LOOK[2])))}
    attachments.add(rig, eyes, [(MUZZLE, "head")])


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "FohossaRig", "Fohossa"
    rigged.flatten(rig, skin)
    scene.select_only(skin)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_faces keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    rename(rig, skin)
    points(rig)
    body = Body(rig)
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, body, clips.WALK, duty=WALK_DUTY, fold=0.0, lift=WALK_LIFT,
                           curl=WALK_CURL, roll=WALK_ROLL, bob=WALK_BOB),
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, body, clips.GALLOP, duty=RUN_DUTY, fold=RUN_FOLD,
                          spine_flex=RUN_SPINE_FLEX, roll=RUN_ROLL, bob=RUN_BOB, planted=False),
        "Attack": lesser(clips.attack()),
        "Hit": lesser(clips.hit()),
        "Faint": clips.faint(BELLY_HEIGHT, forepaws=FAINT_FOREPAWS),
        **{name: lesser(clip) for name, clip in clips.channel().items()},
        "Feed": clips.feed(forepaws=0.04),
        "Sleep": clips.sleep(clips.curled(BELLY_HEIGHT), SLEEP_PAWS),
    }, SCALE, ground_meshes=[skin], chains=FOLLOW, limbs=adopted.limbs(rig),
        overlays=[withers])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
