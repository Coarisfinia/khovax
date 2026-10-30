"""The standing stone (#1853), the savepoint (#1854): a slab of stone with a round hole through its
upper middle, in a ring of flat paving stones. Its shape is the owner's generated model, made
without a texture (`sources/standing_stone.glb`, from the download by import_source.py: see the
asset's SOURCE.md); its colours are the props' shared texture set (lib/prop_paint.py, CC0
textures), mapped by this script: weathered stone, moss on its top and ledges, darker crevices and
foot, and the hole's inner wall as its own part (`glow`), which the game lights once the stone is
activated (#1854). No runes: its faces stay free for an engraving (#1855, #1856). A static model:
no rig and no clips.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/standing_stone.py -- packages/game/assets/standing-stone/standing_stone.glb

Blender is Z-up and it faces -Y (the game's +Z), the hole running through along Y; the origin is
at the stone's foot, in the middle of its hex, and it is sized to its hex as a prop
(lib/footprint.py's `PROP`)."""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import footprint, prop_paint, repaint, scene  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "standing_stone.glb")
FPS = 30
# Edges sharper than this stay sharp in the shading: the slab's chiselled facets.
SHARP = math.radians(40.0)

# The hole in the source's own units (before placing and sizing): its axis's x and z, and its
# radius. Faces of the slab within RIM of its radius from the axis, turned toward it, are its
# inner wall.
HOLE_X, HOLE_Z, HOLE_RADIUS = 0.0, 0.05, 0.12
RIM = 1.25
# The rim's colour while unlit: a shaded, faintly blue stone, so the glow's part reads as stone
# until the game lights it.
RIM_COLOUR = (0.52, 0.56, 0.58)
# The materials, in their slots: (name, the set's texture, its grey factor, linear).
MATERIALS = (("stone", "stone", 1.0), ("stone_shaded", "stone", prop_paint.Weathering.shade), ("moss", "moss", 1.0))
STONE, SHADED, MOSS, GLOW = range(4)
# How far a crevice's darkness looks, in metres once sized.
REACH = 0.25


def place(obj):
    """Stands the stone on the ground at the hex's centre and sizes it to its hex as a prop.
    Returns the scale."""
    mesh = obj.data
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    low, high = points.min(axis=0), points.max(axis=0)
    shift = Matrix.Translation((-(low[0] + high[0]) / 2.0, -(low[1] + high[1]) / 2.0, -low[2]))
    mesh.transform(shift)
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    size = footprint.SLACK * footprint.PROP[0] / footprint.spread(points)
    mesh.transform(Matrix.Scale(size, 4))
    mesh.update()
    return size, shift


def subdivide(obj, faces):
    """Cuts each of `faces` into four, flat: the paint's bands follow the tone between vertices, so
    the slab, seen up close, gets more of them."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    work.faces.ensure_lookup_table()
    edges = sorted({edge.index for index in faces for edge in work.faces[index].edges})
    work.edges.ensure_lookup_table()
    bmesh.ops.subdivide_edges(work, edges=[work.edges[index] for index in edges], cuts=1, use_grid_fill=True)
    work.to_mesh(obj.data)
    work.free()


def vertex_data(mesh):
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            numpy.array([vertex.normal[:] for vertex in mesh.vertices]))


def slab_vertices(mesh):
    """Whether each vertex is the slab's (the largest piece) rather than a paving stone's."""
    pieces = repaint.pieces(mesh)
    slab = numpy.zeros(len(mesh.vertices), dtype=bool)
    for polygon in mesh.polygons:
        if pieces[polygon.index] == 0:
            slab[list(polygon.vertices)] = True
    return slab


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    stone = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    stone.name = stone.data.name = "StandingStone"
    scene.select_only(stone)
    # The source's normals come back as custom ones, which sort_mesh refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    size, shift = place(stone)
    # The hole's axis, moved and sized with the stone.
    axis_x = (HOLE_X + shift.translation[0]) * size
    axis_z = (HOLE_Z + shift.translation[2]) * size
    radius = HOLE_RADIUS * size

    pieces = repaint.pieces(stone.data)
    subdivide(stone, sorted(face for face, piece in pieces.items() if piece == 0))
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    mesh = stone.data
    for name, texture, factor in MATERIALS:
        mesh.materials.append(prop_paint.material(name, texture, factor))
    mesh.materials.append(prop_paint.glow("glow", RIM_COLOUR))

    # Moss on the slab's top and ledges, never on the paving: cut along its edge, then given to
    # the faces above it (the cuts keep a face's material, so the next cut keeps the moss).
    slab = slab_vertices(mesh)
    points, normals = vertex_data(mesh)
    moss = numpy.where(slab, prop_paint.mossiness(points, normals), -1.0)
    moss = prop_paint.contour(mesh, moss, 0.0)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, moss, 0.0)):
        polygon.material_index = MOSS if above else STONE

    # The shaded step: crevices, and the slab's foot (the paving lies on the ground whole, so
    # only its cracks darken).
    slab = slab_vertices(mesh)
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(stone, points, normals, REACH)
    dark = numpy.where(slab, prop_paint.darkness(points, shut), prop_paint.darkness(points, shut, foot=False))
    dark = prop_paint.contour(mesh, dark, prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        if above and polygon.material_index == STONE:
            polygon.material_index = SHADED

    # The hole's inner wall: slab faces near the axis, turned toward it.
    pieces = repaint.pieces(mesh)
    rim = 0
    for polygon in mesh.polygons:
        centre = polygon.center
        inward = numpy.array((axis_x - centre.x, axis_z - centre.z))
        distance = float(numpy.hypot(*inward))
        if pieces[polygon.index] == 0 and distance < radius * RIM and \
                float(numpy.dot(inward / max(distance, 1e-9), (polygon.normal.x, polygon.normal.z))) > 0.5:
            polygon.material_index = GLOW
            rim += 1
    prop_paint.box_uv(mesh)

    points, _normals = vertex_data(mesh)
    counts = numpy.bincount([polygon.material_index for polygon in mesh.polygons], minlength=len(mesh.materials))
    print("BUDGET triangles", scene.triangles(stone), "materials", len(mesh.materials),
          "textures %dx%d" % tuple(bpy.data.images["stone"].size), "scale %.4f" % size,
          "height %.3f" % points[:, 2].max(), "faces per material", dict(zip([m.name for m in mesh.materials], counts.tolist())),
          "reach %.3f" % footprint.spread(points))
    scene.export_glb(out)


main()
