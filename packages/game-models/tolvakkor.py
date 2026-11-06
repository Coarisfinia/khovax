"""The Tolvakkor (#1770): the Kalvrakkor's ice form, the frost side taken over the whole hound, in
a full suit of ice armour under a helmet with a crest of frost feathers. Its mesh, paint and rig
come from the owner's generated model (`sources/tolvakkor.glb`, made by import_source.py from the
download, fitted to its hex as a large monster: see the asset's SOURCE.md). The owner's vibe: "armored
frost doggy incoming. very sturdy vibe.", so it moves as a heavy thing: short lifts of its paws, a
shallow bob, a slow wind-up to its Attack, a helmet-first slam, and a blow barely shifts it.

Its armour is what the generator modelled: the plates on its back, chest and legs are one piece
with its skin, and each pauldron is a separate piece that the generator's weights pulled apart
between its neck, its shoulder and its leg. So every separate piece on its shoulders rides whole
on the chest and its upper arm (ARMOUR): the armour moves with the body and doesn't bend.

It names the generator's bones to the library's quadruped scheme and animates every creature clip
with the library's clips, its legs planted by lib/adopted.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/tolvakkor.py -- packages/game/assets/tolvakkor/tolvakkor.glb

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
import numpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import adopted, attachments, clips, legs, marked_eyes, metrics, repaint, rigged, scene, tuning  # noqa: E402
from lib.materials import palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "tolvakkor.glb")
FPS = 30
SCALE = 1.0

# --- Its eyes ----------------------------------------------------------------------------------
# Dark eyeballs and a pale ice glow, under the helmet's brow: its helmet is its brow, so ours is small.
COLORS = {
    "dark": ((0.02, 0.03, 0.05, 1.0), 0.0),
    "glow": ((0.25, 0.7, 1.0, 1.0), 1.0),
}
# Its helmet's cheeks fall away steeply, which would turn the eyes far outward, so they aim straight
# ahead (the blind review measured them wall-eyed).
EYE_SHAPE = {"pupil": (0.3, 0.45), "brow_size": 0.85, "rim": True, "forward": (0.1, -1.0, 0.0)}
# The generator's dark ovals are a little lighter than the library's dark, and small: its eyes,
# on either side of the head's midline once the head is straight (HEAD_TURN), are a little larger.
EYE_DARK = 0.3
HEAD_MIDDLE = -0.018
EYE_GROW = 1.1
# Faint's frames over which the lids shut (eyes.Lids): as it sinks.
FAINT_LIDS = (18, 40)

# --- The rig -----------------------------------------------------------------------------------
# Weights first go from the bones that go to the ones that stay: the second trunk bone into the
# first, the neck's three bones into one, the two shoulder chains and their stubs into the upper
# arms, the helmet's and the snout's chains into the head (its mouth doesn't open), the crest's
# empty middle bones into its tips, and each paw's toe bone into the bone above it, so the paw the
# clips plant is the whole foot.
MERGES = {
    "chain1_02": "chain1_01", "chain2_02": "chain2_01", "chain2_03": "chain2_01",
    "chain3_01": "leg_01.R", "chain3_02": "leg_01.R", "chain4_01": "leg_01.R", "chain4_02": "leg_01.R",
    "chain5_01": "front_leg_01", "chain5_02": "front_leg_01", "chain6_01": "front_leg_01",
    "chain6_02": "front_leg_01",
    "chain7_01": "chain7_02", "chain8_01": "chain7_02", "chain8_02": "chain7_02",
    "chain9_02": "chain9_03", "chain10_02": "chain10_03",
    "paw.R": "leg_03.R", "front_paw": "front_leg_03", "hind_paw": "hind_leg_04", "paw.L": "leg_04.L",
}
RENAMES = {
    "chain1_01": "spine_02", "chain2_01": "neck", "chain7_02": "head",
    "chain9_01": "ear.L", "chain9_03": "ear_tip.L", "chain10_01": "ear.R", "chain10_03": "ear_tip.R",
    **{"stalk_%02d.L" % number: "tail_%02d" % number for number in range(1, 6)},
    "leg_01.R": "upper_arm.R", "leg_02.R": "forearm.R", "leg_03.R": "front_paw.R",
    "front_leg_01": "upper_arm.L", "front_leg_02": "forearm.L", "front_leg_03": "front_paw.L",
    "hind_leg_01": "thigh.R", "hind_leg_02": "shin.R", "hind_leg_03": "hock.R", "hind_leg_04": "hind_paw.R",
    "leg_01.L": "thigh.L", "leg_02.L": "shin.L", "leg_03.L": "hock.L", "leg_04.L": "hind_paw.L",
}
# Where the head turns on the neck (the head bone then runs from here to the tip of its nose, which
# it butts with): the generator's head bones stood up inside the helmet.
SKULL = (-0.01, -0.39, 0.78)
NOSE = (-0.02, -0.66, 0.79)
# The generator posed its head turned this far to its left (its eyes aren't level across it, by
# their marks): the head and its crest turn back about the skull's joint, so it looks where it walks.
HEAD_TURN = math.radians(19.5)
HEAD_BONES = ("head", "ear.L", "ear_tip.L", "ear.R", "ear_tip.R")
# The breastplate and the collar stay on the chest: the neck's skin below this line through
# (depth, height) metres, falling toward the front, is the chest's, so a bowing neck doesn't bend
# the plate.
COLLAR = ((-0.05, 0.76), (-0.40, 0.56))
# The legs' tops give the trunk's skin up, as Fohossa's do: above this height, or nearer the
# midline than this (metres, from its middle), the upper arm's skin is the chest's and the thigh's
# the back's, so a swinging leg doesn't drag the armoured trunk thin (the volume check).
TRUNK, BELLY = 0.58, 0.05
# A hip's round plate stays on the trunk too, like the back's armour: the thigh's skin above this
# height is the back's.
HAUNCH = 0.46
MIDDLE = 0.01
# The generator put each hind knee too low, which left a long thigh above a short shin (the
# dimensions check): the knee moves up this share of the thigh, its skin staying where it is, and
# forward (metres), so the hind leg stays bent as it reaches back.
KNEE = 0.88
KNEE_FORWARD = 0.04
# Its forelegs stand almost straight under the shoulder, and a straight leg's joint swings far for a
# small move of its paw, and snaps straight as it lands (the motion check's jitter): each elbow
# moves back and each shoulder's joint forward this far (metres), where a hound's lie, so the
# leg slants back and stays bent.
ELBOW_BACK, SHOULDER_FORWARD = 0.05, 0.06
# Its hind legs slant back from the hip to the paw, so a paw reaching further back straightens the
# leg and snaps it (the jitter again): each hip's joint moves back this far (metres), over the paw.
HIP_BACK = 0.08
# The heel's skin below this height goes from the hock to the hind paw, and the wrist's from the
# forearm to the forepaw, so the whole sole is the paw's and stays where it's planted.
HEEL = 0.09
# A separate piece (of the armour) this high up or higher is the helmet's and its crest's, this
# low or lower a claw: those keep their weights. The pieces between lie on its shoulders.
CREST_ABOVE, CLAW_BELOW = 0.75, 0.15
# How much of its upper arm's swing a shoulder's armour takes; the rest stays with the chest, so a
# pauldron turns a little over the shoulder rather than swinging into the neck.
ARMOUR = 0.5

# The rest of its proportions are measured as notes until the owner approves its look.
REFERENCE = {}

FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith(("ear.", "jaw"))}
# A heavy tail, slower to swing than the wolf's; the crest's feathers still trail the head.
FOLLOW.update({"tail_05": (1.7, 0.45, 0.0, 0.12), "ear_tip.L": (2.4, 0.4, 0.0, 0.1),
               "ear_tip.R": (2.4, 0.4, 0.0, 0.1)})

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s. A heavy beast plants its paws longer and lifts them less.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_TILES, RUN_TILES = 0.7, 1.25
WALK_DUTY, WALK_LIFT, WALK_CURL, WALK_ROLL, WALK_BOB = 0.27, 0.35, 0.3, 0.02, 0.3
RUN_DUTY, RUN_FOLD, RUN_SPINE_FLEX, RUN_ROLL, RUN_BOB = 0.21, 0.5, 0.03, 0.0, 0.2
GAIT = ("KNEE_FORWARD", "HIP_BACK", "SHOULDER_FORWARD", "WALK_TILES", "WALK_DUTY", "WALK_LIFT", "WALK_CURL", "WALK_ROLL", "WALK_BOB", "RUN_TILES", "RUN_DUTY",
        "RUN_FOLD", "RUN_SPINE_FLEX", "RUN_ROLL", "RUN_BOB")
OUT = tuning.arguments(globals(), GAIT)
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * WALK_TILES, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * RUN_TILES, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

# How far it sinks to lie on its belly, lying limp or asleep: as far as its forelegs let it, its
# belly on or near the ground (#2030; animate lifts it where its elbows would sink), and how much
# of the wolf's reach its other clips keep (adopted.lesser). A blow barely shifts it (HIT_SHARE,
# HIT_TURNS).
BELLY_HEIGHT = 0.12
SLEEP_HEIGHT = 0.25
SHARE = 0.5
HIT_SHARE, HIT_TURNS = 0.3, 0.5
# Its neck is long and armoured: lying down, it bows less than a wolf's (the volume check), asleep
# and limp. So its chest tips its front down instead, bringing its head low (adopted.bowed,
# #2030). Asleep its head tips back up on its neck a little, so its eyes look out over its
# forepaws rather than down onto them (the eyes-covered check).
LYING_TURNS = 0.6
FAINT_TURNS = 0.75
SLEEP_BOW = {"spine_02": 0.3, "head": -0.12}
FAINT_BOW = {"spine_02": 0.25}
# Faint's frames over which its bow grows, as it sinks (clips.faint's keys).
FAINT_BOWING = (10, 32)
# A smaller brace than the wolf's: its weight doesn't need to shift far to hold (clips.channel).
BRACE = {"front_paw": (0.03, 0.0, 0.1), "hind_paw": (0.02, 0.0, 0.0)}
# Its tail reaches the hex's corner at rest, so its swings stay small: a heavy tail hardly moves.
TAIL_SHARE = 0.3
# Its long neck and tall stance reach the ground with its chest low, its head tipped down and its
# forepaws out in front (clips.feed).
FEED = {"neck": 0.36, "head": 0.6, "crouch": 0.3, "forepaws": 0.1}
# Lying, its forepaws reach far out in front, so its forelegs lie long and its elbows let its
# chest down onto the ground: folded under it, they'd hold it up in a crouch (#2030).
FAINT_FOREPAWS = 0.4
SLEEP_PAWS = {"front_paw": (0.0, 0.0, 0.44), "hind_paw": (0.09, 0.0, -0.09)}


def slam():
    """Its Attack: not a wolf's snap but a heavy charge. A slow wind-up, its weight sinking back
    and its head tucked behind the helmet; a lurch forward, helmet first, its forepaws stamping
    down at the end of it; then it rocks back, sways past where it stood and settles slowly."""
    wind = {"root_loc": (0, -0.05, -0.10), "hips": (-0.07, 0, 0), "neck": (0.12, 0, 0), "head": (0.12, 0, 0),
            "tail_01": (-0.12, 0, 0)}
    held = dict(wind, root_loc=(0, -0.06, -0.12), hips=(-0.08, 0, 0), head=(0.15, 0, 0))
    ram = {"root_loc": (0, -0.02, 0.20), "hips": (0.05, 0, 0), "neck": (0.16, 0, 0), "head": (0.30, 0, 0),
           "tail_01": (0.16, 0, 0)}
    landed = dict(ram, root_loc=(0, -0.03, 0.22), head=(0.36, 0, 0))
    back = {"root_loc": (0, -0.01, 0.05), "hips": (0.01, 0, 0), "neck": (0.03, 0, 0), "head": (0.05, 0, 0),
            "tail_01": (0.05, 0, 0)}
    past = {"root_loc": (0, 0.0, -0.02), "hips": (-0.015, 0, 0), "neck": (-0.02, 0, 0), "head": (-0.02, 0, 0),
            "tail_01": (-0.03, 0, 0)}
    steps = []
    for side, late in (("L", 0), ("R", 2)):
        steps.append(legs.Step("front_paw." + side, 15 + late, 23 + late, (0.0, 0.0, 0.2), 0.08))
        steps.append(legs.Step("front_paw." + side, 30 + late, 40 + late, (0.0, 0.0, 0.0), 0.05))
    return clips.Clip([(1, {}), (12, wind), (16, held), (22, ram, "quart"), (25, landed), (34, back), (42, past),
                       (50, {})], steps=steps)


def shoulder_pieces(skin):
    """The vertices of each separate piece lying on the shoulders, by side ("L", "R"): neither the
    body (the largest piece), nor the crest's, nor a claw."""
    piece = repaint.pieces(skin.data)
    faces = {}
    for face, number in piece.items():
        faces.setdefault(number, []).append(face)
    body = max(faces, key=lambda number: len(faces[number]))
    out = {"L": set(), "R": set()}
    for number, members in faces.items():
        middle = numpy.mean([skin.data.polygons[face].center[:] for face in members], axis=0)
        if number != body and CLAW_BELOW < middle[2] < CREST_ABOVE:
            side = "L" if middle[0] > MIDDLE else "R"
            out[side].update(index for face in members for index in skin.data.polygons[face].vertices)
    print("ARMOUR %d vertices on the left shoulder, %d on the right" % (len(out["L"]), len(out["R"])))
    return out


def weigh(skin):
    """The trunk's, the neck's and the heels' skin to the bones that should hold them, once the
    bones are named; then the shoulders' armour whole on the chest and its upper arm."""
    pieces = shoulder_pieces(skin)
    rigged.merge(skin, {"thigh.L": "spine_01", "thigh.R": "spine_01"},
                 lambda vertex: vertex.co.z > HAUNCH or abs(vertex.co.x - MIDDLE) < BELLY)
    rigged.merge(skin, {"upper_arm.L": "spine_02", "upper_arm.R": "spine_02"},
                 lambda vertex: vertex.co.z > TRUNK or abs(vertex.co.x - MIDDLE) < BELLY)
    (near_y, near_z), (far_y, far_z) = COLLAR
    slope = (far_z - near_z) / (far_y - near_y)
    rigged.merge(skin, {"neck": "spine_02"}, lambda vertex: vertex.co.z < near_z + slope * (vertex.co.y - near_y))
    rigged.merge(skin, {"hock.L": "hind_paw.L", "hock.R": "hind_paw.R", "forearm.L": "front_paw.L",
                        "forearm.R": "front_paw.R"}, lambda vertex: vertex.co.z < HEEL)
    for side, indices in pieces.items():
        for index in sorted(indices):
            for group in list(skin.vertex_groups):
                group.remove([index])
            skin.vertex_groups["spine_02"].add([index], 1.0 - ARMOUR, "REPLACE")
            skin.vertex_groups["upper_arm." + side].add([index], ARMOUR, "REPLACE")


def rename(rig, skin):
    rigged.merge(skin, MERGES)
    for name in MERGES:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    # Each foot's toe bone goes into the bone above it, which reaches to the toe's tip.
    for keep, toe in (("leg_03.R", "paw.R"), ("front_leg_03", "front_paw"), ("hind_leg_04", "hind_paw"),
                      ("leg_04.L", "paw.L")):
        edit[keep].tail = edit[toe].tail
        edit.remove(edit[toe])
    for thigh, shin in (("hind_leg_01", "hind_leg_02"), ("leg_01.L", "leg_02.L")):
        knee = edit[thigh].head.lerp(edit[thigh].tail, KNEE) - Vector((0.0, KNEE_FORWARD, 0.0))
        edit[thigh].tail = knee
        edit[thigh].head.y += HIP_BACK
        edit[shin].head = knee
    for upper, lower in (("leg_01.R", "leg_02.R"), ("front_leg_01", "front_leg_02")):
        elbow = edit[upper].tail + Vector((0.0, ELBOW_BACK, 0.0))
        edit[upper].tail = elbow
        edit[upper].head.y -= SHOULDER_FORWARD
        edit[lower].head = elbow
    # The generator hung its hind legs from the chest and its forelegs from the neck.
    chest, neck, head, hips = edit["chain1_01"], edit["chain2_01"], edit["chain7_02"], edit["hips"]
    for name in ("hind_leg_01", "leg_01.L", "stalk_01.L"):
        edit[name].use_connect = False
        edit[name].parent = hips
    for name in ("leg_01.R", "front_leg_01"):
        edit[name].use_connect = False
        edit[name].parent = chest
    chest.tail = neck.head
    neck.use_connect = False
    neck.parent = chest
    neck.tail = Vector(SKULL)
    head.use_connect = False
    head.parent = neck
    head.head, head.tail = Vector(SKULL), Vector(NOSE)
    for first, tip, middle in (("chain9_01", "chain9_03", "chain9_02"), ("chain10_01", "chain10_03", "chain10_02")):
        edit[first].use_connect = False
        edit[first].parent = head
        edit[tip].use_connect = False
        edit[tip].parent = edit[first]
        edit[tip].head = edit[first].tail
        edit.remove(edit[middle])
    for name in ("chain1_02", "chain2_02", "chain2_03", "chain3_01", "chain3_02", "chain4_01", "chain4_02",
                 "chain5_01", "chain5_02", "chain6_01", "chain6_02", "chain7_01", "chain8_01", "chain8_02"):
        edit.remove(edit[name])
    bpy.ops.object.mode_set(mode="OBJECT")
    rigged.rename(rig, skin, RENAMES)
    rigged.roll(rig)


def straighten(rig, skin):
    """Turns the head back to face ahead, each vertex as far as the head's bones hold it, and the
    crest's bones with it."""
    turn = Matrix.Translation(SKULL) @ Matrix.Rotation(-HEAD_TURN, 4, "Z") @ Matrix.Translation(-Vector(SKULL))
    held = {skin.vertex_groups[name].index for name in HEAD_BONES}
    for vertex in skin.data.vertices:
        share = sum(element.weight for element in vertex.groups if element.group in held)
        if share > 0.0:
            vertex.co = vertex.co.lerp(turn @ vertex.co, share)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name in HEAD_BONES[1:]:
        bone = rig.data.edit_bones[name]
        bone.head, bone.tail = turn @ bone.head, turn @ bone.tail
    bpy.ops.object.mode_set(mode="OBJECT")
    rigged.roll(rig)


def limbs(rig):
    """The legs for the clips: adopted's, but each hind leg bends at its knee, its shin and hock one
    run below it; adopted's bends at the hock, where the leg stands straight and snaps as it reaches
    back (the motion check's jitter)."""
    bones = rig.data.bones
    out = [leg for leg in adopted.limbs(rig) if not leg.paw.startswith("hind_paw")]
    for side in ("L", "R"):
        top, bend, foot = (bones["thigh." + side].head_local, bones["shin." + side].head_local,
                           bones["hind_paw." + side].head_local)
        out.append(legs.Leg(("thigh." + side,), ("shin." + side, "hock." + side), "hind_paw." + side,
                            plane=tuple((bend - top).cross(foot - bend).normalized())))
    return out


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "TolvakkorRig", "Tolvakkor"
    rigged.flatten(rig, skin)
    scene.select_only(skin)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    rename(rig, skin)
    weigh(skin)
    straighten(rig, skin)
    marked = marked_eyes.Marked("DARK", lambda colours: colours.max(axis=1) <= EYE_DARK, middle=HEAD_MIDDLE)
    lids, spots = marked_eyes.replace(rig, skin, palette(COLORS), FAINT_LIDS, marked=marked, grow=EYE_GROW,
                                      **EYE_SHAPE)
    attachments.add(rig, spots, [(NOSE, "head")])
    body = adopted.Body(rig, NOSE)
    clips.animate(rig, {
        "Idle": adopted.lesser(clips.idle(breath=120), TAIL_SHARE),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, body, clips.WALK, duty=WALK_DUTY, fold=0.0, lift=WALK_LIFT,
                           curl=WALK_CURL, roll=WALK_ROLL, bob=WALK_BOB),
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, body, clips.GALLOP, duty=RUN_DUTY, fold=RUN_FOLD,
                          spine_flex=RUN_SPINE_FLEX, roll=RUN_ROLL, bob=RUN_BOB, planted=False),
        "Attack": slam(),
        "Hit": adopted.lesser(clips.hit(), HIT_SHARE, turns=HIT_TURNS),
        "Faint": adopted.bowed(adopted.lesser(clips.faint(BELLY_HEIGHT, forepaws=FAINT_FOREPAWS), 1.0,
                                              turns=FAINT_TURNS), FAINT_BOW, *FAINT_BOWING),
        **{name: adopted.lesser(clip, SHARE) for name, clip in clips.channel(brace=BRACE).items()},
        "Feed": adopted.lesser(clips.feed(**FEED), TAIL_SHARE),
        "Sleep": adopted.bowed(adopted.lesser(clips.sleep(clips.curled(SLEEP_HEIGHT), SLEEP_PAWS), 1.0,
                                              turns=LYING_TURNS), SLEEP_BOW),
    }, SCALE, ground_meshes=[skin], chains=FOLLOW, limbs=limbs(rig), overlays=[lids.shut])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
