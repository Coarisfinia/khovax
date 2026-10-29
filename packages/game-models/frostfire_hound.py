"""The Frostfire Hound (#1609): a lean, long-eared hound, magma on its right side and ice on its
left, with one magma tail and one icy tail. Its mesh and rig come from the owner's generated
model (`sources/frostfire_hound.glb`, made by import_source.py from the download, fitted to its
hex as a regular monster: see the asset's SOURCE.md). The generator's paint was a patchwork, so
this script paints the texture anew from where each texel lies on the body (lib/repaint.py), as
the owner asked on the issue:

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

from lib import adopted, attachments, clips, metrics, repaint, rigged, scene, tuning  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "frostfire_hound.glb")
FPS = 30
SCALE = 1.0

# --- The paint ---------------------------------------------------------------------------------
# The texture's size (texels a side): the generator's atlas, at the source's size.
TEXTURE = 1024
# The glow's texture is coarser: only the cracks and eyes glow, and they are soft.
GLOW_TEXTURE = 512
# The midline between the two sides (metres along X): the generator's model stands a little to
# its right of the origin (its legs' middle).
MIDLINE = -0.035
# The cracks: one cell of rock or ice about this wide (metres), from a fixed seed; a crack is this
# wide at its middle, and the magma's glow reaches this far into the rock beside it.
CELL = 0.09
SEED = 1609
CRACK = 0.0035
GLOW_REACH = 0.006
# Colours (sRGB): the ice in three tones by cell, its frosted cracks and its pads; the basalt in
# three tones, its glowing cracks (hot at the middle, cooling to the rim) and its pads.
ICE = ((0.36, 0.60, 0.88), (0.42, 0.67, 0.92), (0.31, 0.54, 0.83))
FROST = (0.86, 0.95, 1.00)
ICE_PAD = (0.20, 0.33, 0.55)
BASALT = ((0.17, 0.11, 0.10), (0.21, 0.13, 0.11), (0.13, 0.09, 0.09))
MAGMA_CORE = (1.00, 0.86, 0.42)
MAGMA_RIM = (0.95, 0.38, 0.08)
BASALT_PAD = (0.10, 0.07, 0.07)
# How strongly the magma's cracks glow on their own (the glow texture's scale), and the eyes'.
MAGMA_GLOW = (1.00, 0.45, 0.10)
# Its eyes: the generator modelled each as a piece of its own; the magma eye burns amber and the
# ice eye shines pale cyan.
MAGMA_EYE = (1.00, 0.78, 0.30)
ICE_EYE = (0.62, 0.96, 1.00)
# A sole: a face this far off straight down at most (the cosine of the angle), this low.
SOLE_FACING = -0.6
SOLE_HEIGHT = 0.06

# --- The tails ---------------------------------------------------------------------------------
# Each tail turns out to its own side about where it grows from the rump (radians about Z), so
# the two no longer lie one on the other: the magma tail to the right, the ice tail to the left.
TAIL_SPREAD = math.radians(9.0)

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
# shin (the dimensions check: shin/thigh 1.58); the knee moves down and forward to where the
# stifle is (depth, height in metres; its side stays), and the shin's skin above it goes to the
# thigh.
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


def paint(skin, part):
    """The colour and the glow textures, painted from where each texel lies at rest."""
    texels = repaint.Texels(skin.data, TEXTURE)
    spots = texels.spots
    low, high = spots.min(axis=0), spots.max(axis=0)
    cells = repaint.Cells(low, high, CELL, SEED)
    nearest, border = cells.near(spots)
    names = numpy.array([part[face] for face in texels.faces])
    # Near the midline a cell is magma when its own middle lies on the right: the border between
    # the sides runs along the cracks, so it reads as one more crack, not a line drawn down the
    # back. Further out the side alone decides, so no stray cell crosses over onto a leg.
    middle = numpy.abs(spots[:, 0] - MIDLINE) < CELL / 2.0
    magma = numpy.where(middle, cells.points[nearest][:, 0] < MIDLINE, spots[:, 0] < MIDLINE)
    magma = numpy.where(names == "tail.R", True, numpy.where(names == "tail.L", False, magma))
    tone = nearest % 3
    rock = numpy.array(BASALT)[tone]
    ice = numpy.array(ICE)[tone]
    base = numpy.where(magma[:, None], rock, ice)
    # A crack's middle is 0 and its edge is CRACK out; the magma's rim glows a little beyond.
    depth = numpy.clip(1.0 - border / CRACK, 0.0, 1.0)
    rim = numpy.clip(1.0 - border / (CRACK + GLOW_REACH), 0.0, 1.0)
    hot = numpy.array(MAGMA_RIM) + (numpy.array(MAGMA_CORE) - numpy.array(MAGMA_RIM)) * depth[:, None]
    lava = base + (hot - base) * numpy.maximum(depth, 0.5 * rim * rim)[:, None]
    frost = base + (numpy.array(FROST) - base) * (depth * depth)[:, None]
    colour = numpy.where(magma[:, None], lava, frost)
    glow = numpy.where(magma[:, None], numpy.array(MAGMA_GLOW) * numpy.maximum(depth, 0.5 * rim * rim)[:, None], 0.0)
    # The soles: plain pads, no cracks.
    sole = (texels.normals[:, 2] < SOLE_FACING) & (spots[:, 2] < SOLE_HEIGHT) & (names == "body")
    colour = numpy.where(sole[:, None], numpy.where(magma[:, None], BASALT_PAD, ICE_PAD), colour)
    glow = numpy.where(sole[:, None], 0.0, glow)
    for name, eye in (("eye.R", MAGMA_EYE), ("eye.L", ICE_EYE)):
        mine = names == name
        colour[mine] = eye
        glow[mine] = eye
    covered = texels.covered()
    canvas = repaint.dilate(texels.paint(texels.canvas(ICE[0]), colour), covered, 4)
    shine = repaint.dilate(texels.paint(texels.canvas((0.0, 0.0, 0.0)), glow), covered, 4)
    # The glow's texture at half the size: the mean of each 2x2 block.
    step = TEXTURE // GLOW_TEXTURE
    shine = shine.reshape(GLOW_TEXTURE, step, GLOW_TEXTURE, step, 3).mean(axis=(1, 3))
    print("PAINT texels %d of %d, magma %.0f%%, soles %d, cells %d" % (
        len(spots), TEXTURE * TEXTURE, 100.0 * magma[names == "body"].mean(), sole.sum(), len(set(nearest.tolist()))))
    return repaint.image("frostfire_hound", canvas), repaint.image("frostfire_hound_glow", shine)


def material(skin, colour, glow):
    """One material: the painted colour, the glow, matte and single-sided."""
    out = bpy.data.materials.new("frostfire_hound")
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


def spread(skin, part):
    """Swings each tail out to its own side about the point where it meets the rump."""
    for name, turn in (("tail.R", -TAIL_SPREAD), ("tail.L", TAIL_SPREAD)):
        indices = sorted({index for face, owner in part.items() if owner == name
                          for index in skin.data.polygons[face].vertices})
        points = [skin.data.vertices[index].co for index in indices]
        root = min(points, key=lambda point: point.y).copy()
        # Turning to the right (-X) as it runs back (+Y) is a turn about +Z the other way.
        matrix = Matrix.Translation(root) @ Matrix.Rotation(-turn, 4, "Z") @ Matrix.Translation(-root)
        for index in indices:
            skin.data.vertices[index].co = matrix @ skin.data.vertices[index].co


# --- Rig ---------------------------------------------------------------------------------------
class Body:
    """What clips.gait reads of a quadruped.Proportions, from the adopted rig."""

    def __init__(self, rig):
        bones = rig.data.bones
        self.front_leg = [tuple(bones["upper_arm.L"].head_local), tuple(bones["front_paw.L"].tail_local)]
        self.hind_leg = [tuple(bones["thigh.L"].head_local), tuple(bones["hind_paw.L"].tail_local)]
        self.hips = tuple(bones["hips"].head_local)
        self.chest = tuple(bones["neck"].head_local)
        self.nose = MUZZLE


def lesser(clip, share=SHARE):
    """`clip` with its body's shifts, its paws' moves and its tail's swing `share` as large: the
    wolf's clips the library's are made for reach too far for its hex."""
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


def merge(skin, weights, where=lambda vertex: True):
    """Moves the weights of the vertices `where` holds as {from bone: to bone} says."""
    groups = {group.index: group.name for group in skin.vertex_groups}
    moves = [(vertex.index, groups[element.group], element.weight)
             for vertex in skin.data.vertices if where(vertex)
             for element in vertex.groups if groups[element.group] in weights and element.weight > 0.0]
    for index, name, weight in moves:
        skin.vertex_groups[name].remove([index])
        (skin.vertex_groups.get(weights[name]) or skin.vertex_groups.new(name=weights[name])).add(
            [index], weight, "ADD")


def rename(rig, skin):
    rigged.rename(rig, skin, {old: new for old, new in RENAMES.items() if old in rig.data.bones})
    # Each foreleg's toe bone goes into its paw, so the paw the clips plant is the whole foot.
    merge(skin, {"front_toe.L": "front_paw.L", "front_toe.R": "front_paw.R"})
    # The throat and the nape go from the chest to the new neck.
    merge(skin, {"spine_01": "neck"}, lambda vertex: vertex.co.z > NECK[0] and vertex.co.y < NECK[1])
    merge(skin, {"shin.L": "thigh.L", "shin.R": "thigh.R"}, lambda vertex: vertex.co.z > KNEE[1] + KNEE_BLEND)
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
    colour, glow = paint(skin, part)
    material(skin, colour, glow)
    spread(skin, part)
    spots = eyes(skin, part)
    rename(rig, skin)
    points(rig, spots)
    body = Body(rig)
    clips.animate(rig, {
        "Idle": clips.idle(),
        "Walk": clips.gait(WALK_FRAMES, WALK_STRIDE, body, clips.WALK, duty=WALK_DUTY, fold=0.0, lift=WALK_LIFT,
                           curl=WALK_CURL, roll=WALK_ROLL, bob=WALK_BOB),
        "Run": clips.gait(RUN_FRAMES, RUN_STRIDE, body, clips.GALLOP, duty=RUN_DUTY, fold=RUN_FOLD,
                          spine_flex=RUN_SPINE_FLEX, roll=RUN_ROLL, bob=RUN_BOB, planted=False),
        "Attack": lesser(clips.attack()),
        "Hit": lesser(clips.hit()),
        "Faint": lesser(clips.faint(BELLY_HEIGHT, forepaws=FAINT_FOREPAWS)),
        **{name: lesser(clip) for name, clip in clips.channel().items()},
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
