"""The mana gems (#1218): a cluster of large mana crystals growing out of a low rock, the decoration
of the gems tile that rings the mana forest. A static prop: no rig and no clips. Only its
parameters live here; the crystals are the shared library's (packages/game-models/lib/).

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/mana_gems.py -- packages/game/assets/mana-gems/mana_gems.glb

Blender is Z-up; the origin is at the rock's foot, in the middle of its tile. Sizes are in the
hexagon pack's units, which the game shrinks to fit a tile (TileDecorations.MODEL_SCALE).
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import parts, scene  # noqa: E402
from lib.materials import palette  # noqa: E402

FPS = 30

# The mana wolf's glow (mana_wolf.py), so the forest and its wolf read as one kind of mana, and a
# violet beside it, so the cluster isn't one flat blue.
COLORS = {
    "rock": ((0.16, 0.15, 0.22, 1.0), 0.0),
    "gem": ((0.05, 0.55, 1.0, 1.0), 0.8),
    "violet": ((0.45, 0.25, 0.95, 1.0), 0.6),
}

# The rock the crystals grow from: a squat, uneven heptagon, its corners' distances from the middle.
ROCK_CORNERS = (0.86, 0.74, 0.92, 0.70, 0.88, 0.78, 0.82)
ROCK_HEIGHT = 0.28

# Each crystal: (angle around the middle in degrees, distance out, height, lean outward, width,
# material). The tallest stands near the middle, the rest lean out around it like a crown.
CRYSTALS = (
    (0.0, 0.05, 2.30, 0.10, 0.17, "gem"),
    (35.0, 0.42, 1.55, 0.45, 0.19, "gem"),
    (100.0, 0.38, 1.20, 0.55, 0.20, "violet"),
    (160.0, 0.45, 1.70, 0.40, 0.18, "gem"),
    (215.0, 0.40, 0.95, 0.70, 0.22, "violet"),
    (270.0, 0.44, 1.35, 0.50, 0.19, "gem"),
    (320.0, 0.30, 0.80, 0.80, 0.24, "violet"),
)


def rock(mat):
    """The rock under the crystals: a flat-shaded heptagonal slab, narrower at its top."""
    sides = len(ROCK_CORNERS)
    verts = []
    for scale, z in ((1.0, 0.0), (0.72, ROCK_HEIGHT)):
        for index, radius in enumerate(ROCK_CORNERS):
            angle = 2 * math.pi * index / sides
            verts.append((radius * scale * math.cos(angle), radius * scale * math.sin(angle), z))
    faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, 2 * sides))]
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((index, nxt, sides + nxt, sides + index))
    mesh = bpy.data.meshes.new("Rock")
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("Rock", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def build(out):
    scene.reset(FPS)
    mats = palette(COLORS)
    rock(mats["rock"])
    for angle, distance, height, lean, width, mat in CRYSTALS:
        turn = math.radians(angle)
        out_x, out_y = math.cos(turn), math.sin(turn)
        base = (distance * out_x, distance * out_y, ROCK_HEIGHT * 0.5)
        direction = (lean * out_x, lean * out_y, 1.0)
        parts.crystal("Crystal.%d" % int(angle), base, direction, height, mats[mat], width=width)
    triangles = sum(scene.triangles(obj) for obj in bpy.data.objects if obj.type == "MESH")
    print("MANA GEMS: %d triangles" % triangles)
    scene.export_glb(out)


build(sys.argv[sys.argv.index("--") + 1])
