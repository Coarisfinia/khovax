"""The Frostfire Hound (#1609): a lean, long-eared hound, magma on its right side and ice on its
left, with one magma tail and one icy tail. Its mesh and rig come from the owner's generated
model (`sources/frostfire_hound.glb`, made by import_source.py from the download, fitted to its
hex as a regular monster: see the asset's SOURCE.md). The generator's paint was a patchwork, so
this script paints the texture anew from where each texel lies on the body (lib/frostfire.py,
which its pup, the Kavrikka, shares), as the owner asked on the issue:

- **the magma side:** the whole right side is dark basalt split by glowing cracks, not just the
  shoulder;
- **the ice side:** the left side is pale blue ice with frosted cracks;
- **the tails:** of its two tails, which lay one on the other, one is magma and one is ice, each
  swung a little out to its own side so both read;
- **the soles:** the underside of every paw is a plain pad of its side's colour.

It names the generator's bones to the library's quadruped scheme and animates every creature clip
with the library's clips, its legs planted by lib/adopted.py.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/frostfire_hound.py -- packages/game/assets/frostfire_hound/frostfire_hound.glb

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

from lib import adopted, attachments, clips, frostfire, metrics, repaint, rigged, scene, tuning  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "frostfire_hound.glb")
FPS = 30
SCALE = 1.0

# --- The paint ---------------------------------------------------------------------------------
# The paint the frost-and-fire line shares (lib/frostfire.py): the midline between the two sides
# (metres along X) runs a little to its right of the origin (its legs' middle), where the
# generator's model stands; cells of rock or ice about 9 cm wide; a sole no higher than 6 cm.
LOOK = frostfire.Look("frostfire_hound", midline=-0.035, cell=0.09, seed=1609, crack=0.0035, glow_reach=0.006,
                      sole_height=0.06)

# --- The tails ---------------------------------------------------------------------------------
# Each tail turns out to its own side about where it grows from the rump (radians about Z), so
# the two no longer lie one on the other: the magma tail to the right, the ice tail to the left.
TAIL_SPREAD = math.radians(9.0)
# How far back from its front tip (metres) a tail's vertices count as its root end.
TAIL_ROOT = 0.02

# --- The rig -----------------------------------------------------------------------------------
# The generator's chains (import_source.py named them chainN_NN) to the library's quadruped scheme
# the clips key. The trunk is the hips (the middle of the back) and one chest bone, here
# `spine_01`; a neck is added between the chest and the head (NECK). Each foreleg is an upper arm,
# a forearm and the paw, whose toe bone is folded into it; each hind leg a thigh, a shin, a hock
# and the paw. Its right side is -X.
RENAMES = {
    "chain3_01": "spine_01", "chain6_01": "head", "chain9_01": "muzzle", "chain7_01": "ear.R", "chain8_01": "ear.L",
    **{"chain10_%02d" % number: "tail_%02d" % number for number in range(1, 6)},
    **{"chain%d_%02d" % (chain, number + 1): "%s.%s" % (name, side)
       for chain, side, names in ((4, "R", ("upper_arm", "forearm", "front_paw", "front_toe")),
                                  (5, "L", ("upper_arm", "forearm", "front_paw", "front_toe")),
                                  (1, "R", ("thigh", "shin", "hock", "hind_paw")),
                                  (2, "L", ("thigh", "shin", "hock", "hind_paw")))
       for number, name in enumerate(names)},
}
# The skin above this height and ahead of this depth (metres) that the chest holds is the neck's:
# the throat and the nape, below the head.
NECK = (0.62, -0.19)
# The generator put each hind knee high under the hip, which left a stub of a thigh above a long
# shin (the dimensions check: shin/thigh 1.58); the knee moves down, and a little forward (to a
# smaller Y, still behind the hip), to where the stifle is (Y, height in metres; its side stays),
# and the shin's skin above it goes to the thigh.
KNEE = (0.31, 0.30)
KNEE_BLEND = 0.02

# Its eyes, as the attachment points find them (the eye pieces' middles, filled in by `eyes`),
# looking ahead and a little out; it bites with its muzzle's tip.
EYE_LOOK = (0.25, -1.0, 0.0)
MUZZLE = (0.07, -0.46, 0.66)

# The rest of its proportions are measured as notes until the owner approves its look.
REFERENCE = {}

FOLLOW = {name: value for name, value in clips.FOLLOW.items() if not name.startswith(("ear.", "jaw"))}
FOLLOW.update({"tail_05": (1.9, 0.4, 0.0, 0.15)})

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s.
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_TILES, RUN_TILES = 0.5, 1.25
WALK_DUTY, WALK_LIFT, WALK_CURL, WALK_ROLL, WALK_BOB = 0.4, 0.2, 0.4, 0.05, 0.4
RUN_DUTY, RUN_FOLD, RUN_SPINE_FLEX, RUN_ROLL, RUN_BOB = 0.3, 0.5, 0.06, 0.0, 0.4
GAIT = ("WALK_TILES", "WALK_DUTY", "WALK_LIFT", "WALK_CURL", "WALK_ROLL", "WALK_BOB", "RUN_TILES", "RUN_DUTY",
        "RUN_FOLD", "RUN_SPINE_FLEX", "RUN_ROLL", "RUN_BOB")
OUT = tuning.arguments(globals(), GAIT)
WALK_FRAMES = clips.cycle_frames(WALK_SPEED, TILE * WALK_TILES, FPS)
RUN_FRAMES = clips.cycle_frames(RUN_SPEED, TILE * RUN_TILES, FPS)
WALK_STRIDE = WALK_SPEED * WALK_FRAMES / FPS / SCALE
RUN_STRIDE = RUN_SPEED * RUN_FRAMES / FPS / SCALE

BELLY_HEIGHT = 0.30
SHARE = 0.5
FAINT_FOREPAWS = 0.25
SLEEP_PAWS = {"front_paw": (0.0, 0.0, 0.25), "hind_paw": (0.08, 0.0, -0.08)}


# --- Paint -------------------------------------------------------------------------------------
def parts(skin):
    """The pieces of the mesh: the body, the two tails (the pieces reaching furthest back) and the
    two eyes (the smallest), each tail and eye by its side. Returns {face: part name}."""
    piece = repaint.pieces(skin.data)
    faces = {}
    for face, number in piece.items():
        faces.setdefault(number, []).append(face)
    middles = {number: numpy.mean([skin.data.polygons[face].center[:] for face in members], axis=0)
               for number, members in faces.items()}
    if len(faces) != 5:
        sys.exit("expected the body, two tails and two eyes; found %d pieces" % len(faces))
    tails = sorted((number for number in faces if number != 0), key=lambda number: -middles[number][1])[:2]
    eyes = [number for number in faces if number not in tails and number != 0]
    names = {0: "body"}
    for kind, members in (("tail", tails), ("eye", eyes)):
        right, left = sorted(members, key=lambda number: middles[number][0])
        names[right], names[left] = kind + ".R", kind + ".L"
    return {face: names[number] for face, number in piece.items()}


def spread(skin, part):
    """Swings each tail out to its own side about the point where it meets the rump."""
    for name, turn in (("tail.R", -TAIL_SPREAD), ("tail.L", TAIL_SPREAD)):
        indices = sorted({index for face, owner in part.items() if owner == name
                          for index in skin.data.polygons[face].vertices})
        points = [skin.data.vertices[index].co for index in indices]
        # The pivot: the middle of the tail's root end, its vertices nearest the rump.
        front = min(point.y for point in points)
        ring = [point for point in points if point.y < front + TAIL_ROOT]
        root = sum(ring, Vector()) / len(ring)
        # Turning to the right (-X) as it runs back (+Y) is a turn about +Z the other way.
        matrix = Matrix.Translation(root) @ Matrix.Rotation(-turn, 4, "Z") @ Matrix.Translation(-root)
        for index in indices:
            skin.data.vertices[index].co = matrix @ skin.data.vertices[index].co


# --- Rig ---------------------------------------------------------------------------------------
def rename(rig, skin):
    rigged.rename(rig, skin, {old: new for old, new in RENAMES.items() if old in rig.data.bones})
    # Each foreleg's toe bone goes into its paw, so the paw the clips plant is the whole foot.
    rigged.merge(skin, {"front_toe.L": "front_paw.L", "front_toe.R": "front_paw.R"})
    # The throat and the nape go from the chest to the new neck.
    rigged.merge(skin, {"spine_01": "neck"}, lambda vertex: vertex.co.z > NECK[0] and vertex.co.y < NECK[1])
    rigged.merge(skin, {"shin.L": "thigh.L", "shin.R": "thigh.R"}, lambda vertex: vertex.co.z > KNEE[1] + KNEE_BLEND)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    for side in ("L", "R"):
        toe = edit["front_toe." + side]
        edit["front_paw." + side].tail = toe.tail
        edit.remove(toe)
    for name in ("front_toe.L", "front_toe.R"):
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    for side in ("L", "R"):
        knee = Vector((edit["shin." + side].head.x, KNEE[0], KNEE[1]))
        edit["thigh." + side].tail = knee
        edit["shin." + side].head = knee
    chest, head = edit["spine_01"], edit["head"]
    neck = edit.new("neck")
    neck.head, neck.tail, neck.parent = chest.tail, head.head, chest
    head.parent = neck
    for name in ("ear.L", "ear.R", "muzzle"):
        edit[name].parent = head
    bpy.ops.object.mode_set(mode="OBJECT")
    rigged.roll(rig)


def eyes(skin, part):
    """Each eye piece's middle, its side's eye point."""
    out = {}
    for side in ("L", "R"):
        indices = sorted({index for face, owner in part.items() if owner == "eye." + side
                          for index in skin.data.polygons[face].vertices})
        out[side] = tuple(sum((skin.data.vertices[index].co for index in indices), Vector()) / len(indices))
    return out


def points(rig, spots):
    look = {"L": EYE_LOOK, "R": (-EYE_LOOK[0], EYE_LOOK[1], EYE_LOOK[2])}
    attachments.add(rig, {side: (spot, "head", look[side]) for side, spot in spots.items()}, [(MUZZLE, "head")])


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in [obj for obj in bpy.context.scene.objects if obj not in (rig, skin)]:
        bpy.data.objects.remove(obj)
    rig.name, skin.name = "FrostfireHoundRig", "FrostfireHound"
    rigged.flatten(rig, skin)
    scene.select_only(skin)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    part = parts(skin)
    colour, glow = frostfire.paint(skin, part, LOOK)
    frostfire.material(skin, "frostfire_hound", colour, glow)
    spread(skin, part)
    spots = eyes(skin, part)
    rename(rig, skin)
    points(rig, spots)
    body = adopted.Body(rig, MUZZLE)
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
    }, SCALE, ground_meshes=[skin], chains=FOLLOW, limbs=adopted.limbs(rig))
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(OUT)
