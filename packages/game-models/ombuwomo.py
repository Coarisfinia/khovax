"""The Ombuwomo (#1738): the Ombulumo's middle form, a bud. A round bud of leaves, spotted pale,
wrapped round a soft body that peeks out through the gap between its front leaves, where its face
is; it hops and wobbles along without legs. Its mesh and colour come from the owner's generated
model (`sources/ombuwomo.glb`, made by import_source.py from the download with `static`: see the
asset's SOURCE.md), with the owner's fixes:

- **no legs:** the generator gave it four little feet; they're cut off, and the bud sits on its
  round bottom, as still as the starry egg;
- **one face:** the generator gave it a face on its back too, in the gap between its back leaves;
  a leaf of its own covers that gap, a copy of one of its leaves turned round onto its back, and
  the face's painted eyes under it are painted over;
- **our own eyes** (lib/marked_eyes.py) in place of its front eyes, with lids that blink: the
  generator set two little black discs on its face over the painted eyes; they're cut off, and
  ours are fitted where the painted eyes under them are.

It is rigged and animated as a limbless body without a tail (lib/limbless.py).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/ombuwomo.py -- packages/game/assets/ombuwomo/ombuwomo.glb

It prints the speeds the motion check (packages/game-models/check_motion.py) takes. `NAME=value`
after the output path sets one of its GAIT values (lib/tuning.py), for the gait sweep
(sweep_gait.py).

Blender is Z-up and it faces -Y (the game's +Z); its left is +X. The joints below, and the clips'
shifts, are in the source's metres, once it sits on the ground; SCALE shrinks it onto its hex
first, and the rig is built at that size.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import attachments, clips, limbless, marked_eyes, metrics, repaint, scene, tuning  # noqa: E402
from lib.materials import palette  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "ombuwomo.glb")
FPS = 30
# How much the source is shrunk, so it sits well inside its hex (check_footprint.py): bigger than
# the tadpole it grows from, smaller than the Ombulumo it grows into.
SCALE = 0.5

# A piece of the mesh (connected faces, lib/repaint.py's pieces) lying wholly below this height
# (source metres) is one of the generator's feet.
FOOT_TOP = 0.3
# A piece of fewer corners than this is one of the generator's eye discs, set on the face over its
# painted eyes: cut off too, so our eyes (fitted to the painted ones under them) sit on the skin.
DISC = 100
# The leaf copied onto its back: the lower leaf whose middle lies nearest LEAF (its back left, +X),
# turned about the bud's middle until its middle lies straight behind it (+Y), and moved SPREAD
# times as far out from the middle, so it lies over the leaves either side of the gap; and TUCK
# times as tall above its foot, so its tip ends below the upper back leaves, which lie over it (the
# owner, on #1752: overlapping leaves are offset, one over the other, not cutting through each other).
LEAF = (0.48, 0.34, 0.76)
SPREAD = 1.06
TUCK = 0.92

# Its joints, along the middle of the bud once it sits on the ground: the face's front, where the
# face gives way to the body, and the body's back.
BODY = limbless.Body(nose=(0.0, -0.86, 0.62), head_base=(0.0, -0.1, 0.66), back=(0.0, 0.86, 0.66))

# Our eyes' colours: the dark eyeball and pupil, and a warm amber glow, which the pale lime spots
# on its leaves don't swallow.
COLORS = {
    "dark": ((0.02, 0.03, 0.03, 1.0), 0.0),
    "glow": ((1.0, 0.62, 0.12, 1.0), 1.0),
}
# A round, gentle bud's eyes: a wide round pupil and a soft brow, twice as large as the
# painted marks, which are half the size of the black discs the generator set over them as its eyes.
EYE_SHAPE = {"pupil": (0.4, 0.5), "brow_size": 0.4, "grow": 2.0}
# It butts with its face's front.
SNOUT = (0.0, -0.84, 0.55)

# Its eyes mirror each other (lib/metrics.py); the rest of its proportions are measured as notes
# until the owner approves its look.
REFERENCE = {
    "eye.R/eye.L height": 0.0,
    "eye.R/eye.L depth": 0.0,
    "eye.R/eye.L sides": 0.0,
}

# The game's speeds (metres a second): a wild monster glides a tile (sqrt(3) apart) in 0.8 s, a
# companion follows at a tile every 0.3 s. It has no feet to slide, so its hop's pace is its own:
# each gait's frames a loop, its wobble (radians) and its hop (source metres).
TILE = math.sqrt(3.0)
WALK_SPEED = TILE / 0.8
RUN_SPEED = TILE / 0.3
WALK_FRAMES, WALK_SWAY, WALK_HOP = 24, 0.28, 0.08
RUN_FRAMES, RUN_SWAY, RUN_HOP = 14, 0.36, 0.16
GAIT = ("WALK_FRAMES", "WALK_SWAY", "WALK_HOP", "RUN_FRAMES", "RUN_SWAY", "RUN_HOP")

# Faint's frames over which the lids shut (eyes.Lids): as it tips over.
FAINT_LIDS = (14, 32)


def reshape(skin):
    """The owner's fixes to the mesh (source metres): its feet and eye discs cut off, a copy of the LEAF leaf
    over the gap on its back, and the bud set down on its round bottom."""
    mesh = skin.data
    piece = repaint.pieces(mesh)
    faces = {}
    for face, number in piece.items():
        faces.setdefault(number, []).append(face)
    corners = {number: [mesh.vertices[index].co for face in found for index in mesh.polygons[face].vertices]
               for number, found in faces.items()}
    feet = sorted(number for number, spots in corners.items() if max(spot.z for spot in spots) < FOOT_TOP)
    discs = sorted(number for number, spots in corners.items() if len(spots) < DISC)

    def middle(number):
        return sum(corners[number], Vector()) / len(corners[number])

    leaf = min((number for number in corners if number not in feet + discs), key=lambda number: (middle(number) - Vector(LEAF)).length)
    centre = middle(leaf)
    turn = Matrix.Rotation(math.pi / 2.0 - math.atan2(centre.y, centre.x), 4, "Z")
    work = bmesh.new()
    work.from_mesh(mesh)
    work.faces.ensure_lookup_table()
    cut = [work.faces[face] for number in feet + discs for face in faces[number]]
    copied = bmesh.ops.duplicate(work, geom=[work.faces[face] for face in faces[leaf]])["geom"]
    verts = [item for item in copied if isinstance(item, bmesh.types.BMVert)]
    foot = min(vert.co.z for vert in verts)
    spread = (Matrix.Translation((0.0, 0.0, foot)) @ Matrix.Diagonal((SPREAD, SPREAD, TUCK, 1.0))
              @ Matrix.Translation((0.0, 0.0, -foot)))
    bmesh.ops.transform(work, matrix=spread @ turn, verts=verts)
    bmesh.ops.delete(work, geom=cut, context="FACES")
    low = min(vert.co.z for vert in work.verts)
    bmesh.ops.translate(work, vec=(0.0, 0.0, -low), verts=work.verts)
    work.to_mesh(mesh)
    work.free()
    mesh.update()
    print("RESHAPE feet cut off: %d pieces, eye discs: %d; leaf copied onto its back: piece %d, turned %.1f degrees; "
          "set down %.3f" % (len(feet), len(discs), leaf, math.degrees(math.pi / 2.0 - math.atan2(centre.y, centre.x)), low))


def build(out):
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    skin = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    skin.name = "Ombuwomo"
    scene.select_only(skin)
    # The import keeps the file's normals as custom ones; smooth normals from the faces shade the
    # same and bend with the skin (scene.sort_mesh keeps no custom normals).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    reshape(skin)
    bpy.ops.object.shade_smooth()
    # Sized first: the eyes are fitted to the marks on the skin and bound to the rig at once, so
    # the rig is built at the game's size around the shrunk skin.
    scene.apply_scale([skin], SCALE)
    rig = limbless.armature("OmbuwomoRig", limbless.scaled(BODY, SCALE))
    limbless.bind(skin, rig)
    # The face on its back, under the copied leaf: its painted eyes go, so none shows past the leaf.
    back = marked_eyes.Head(skin, limbless.BODY)
    marked_eyes.repaint(back, marked_eyes.find(back))
    lids, eyes = marked_eyes.replace(rig, skin, palette(COLORS), FAINT_LIDS, **EYE_SHAPE)
    attachments.add(rig, eyes, [(tuple(SCALE * value for value in SNOUT), limbless.HEAD)])
    clips.animate(rig, {
        "Idle": limbless.idle(0),
        "Walk": limbless.wriggle(0, WALK_FRAMES, WALK_SWAY, WALK_HOP),
        "Run": limbless.wriggle(0, RUN_FRAMES, RUN_SWAY, RUN_HOP, surge=0.06),
        "Attack": limbless.attack(0),
        "Hit": limbless.hit(0),
        "Faint": limbless.faint(0),
        **limbless.channel(0),
        "Feed": limbless.feed(0),
        "Sleep": limbless.sleep(0),
    }, SCALE, ground_meshes=[skin], chains=limbless.follow(0), limbs=(), overlays=[lids.shut])
    scene.export_glb(out)
    print("MODEL", out, "triangles", scene.triangles(skin), "bones", len(rig.data.bones),
          "materials", len(skin.data.materials))
    print("SPEEDS Walk=%.3f Run=%.3f" % (WALK_SPEED, RUN_SPEED))
    if not metrics.report(rig, [skin], REFERENCE):
        sys.exit(1)


build(tuning.arguments(globals(), GAIT))
