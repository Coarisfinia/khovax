"""Copper ore (#1949), the copper material's carried model: a few chunks of stone with flat ribbons
of copper curling out of the cracks between them. Its shape is the owner's generated model, made
without a texture (`sources/copper_ribbons_ore.glb`, from the download by import_source.py: see the
asset's SOURCE.md), and the source stays as the owner made it: this script makes the owner's fix.
One of its ribbons leaves the stone as two strands that merge into one curl; the owner asked for
that ribbon to go, both strands and the curl, since enough ribbons come out of the stone without
it. Its colours are the props' shared stone (lib/prop_paint.py, CC0 textures) with a darker
shaded step, and the ribbons one flat copper tint (`prop_paint.flat`), the ore outcrop's veins'.
Every ore has a model of its own (#1949, #1950), so this is not the outcrop scaled down. A static
model: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/copper_ribbons_ore.py -- \
        resourcepacks/default/models/copper-ribbons-ore/copper_ribbons_ore.glb

Blender is Z-up; the origin is at the stone's foot, in its middle, and it is sized to be carried in
a hand, like the stone material's pebble."""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import fixed_order, prop_paint, repaint, scene  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "copper_ribbons_ore.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a thing a hand carries.
WORLD_SCALE = "item"
# Its longest side once sized, in metres: a lump a hand carries, the pebble's size.
SIZE = 0.4
# Edges sharper than this stay sharp in the shading: the chunks' broken facets.
SHARP = math.radians(40.0)
# The ribbons' colour: the ore outcrop's copper veins (ore_outcrop.py), as a flat tint (sRGB).
COPPER = (0.86, 0.50, 0.22)
# The materials, in their slots.
STONE, SHADED, RIBBONS = range(3)
# A piece whose foot is this close to the model's lowest point stands on the ground: a chunk of
# stone. The ribbons start in the cracks, above it (in the source's units).
GROUND = 0.02
# A point in the source (Blender's axes, its units) inside the split ribbon only: where its two
# strands leave the stone at the back and merge.
SPLIT = Vector((0.0, 0.30, -0.12))
# How much nearer the split ribbon must be to SPLIT than any other ribbon, so a changed source
# fails here rather than losing another ribbon.
MARGIN = 0.05
# How far a crevice's darkness looks, in metres once sized: the narrow joins between the chunks.
REACH = 0.05


def weld(obj):
    """Joins the seam splits by position, so the surface shades whole, not island by island (the
    starry egg's trap, model skill), in a fixed order (lib/fixed_order.py)."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    fixed_order.weld(work)
    work.to_mesh(obj.data)
    work.free()


def ribbons_and_split(mesh):
    """The pieces that are ribbons (the rest stand on the ground: the stone) and the ribbon to
    remove, the one nearest SPLIT."""
    piece_of = repaint.pieces(mesh)
    low = {}
    for polygon in mesh.polygons:
        foot = min(mesh.vertices[index].co.z for index in polygon.vertices)
        number = piece_of[polygon.index]
        low[number] = min(low.get(number, foot), foot)
    bottom = min(low.values())
    ribbons = sorted(number for number, foot in low.items() if foot > bottom + GROUND)
    nearest = {}
    for polygon in mesh.polygons:
        number = piece_of[polygon.index]
        if number in ribbons:
            distance = (polygon.center - SPLIT).length
            nearest[number] = min(nearest.get(number, distance), distance)
    ranked = sorted(ribbons, key=lambda number: (nearest[number], number))
    if len(ranked) < 2 or nearest[ranked[1]] - nearest[ranked[0]] < MARGIN:
        raise SystemExit("the split ribbon isn't clearly the one nearest SPLIT: %s" % nearest)
    return piece_of, set(ribbons), ranked[0]


def remove(obj, faces):
    """Deletes `faces` (indices) and what only they used."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    work.faces.ensure_lookup_table()
    bmesh.ops.delete(work, geom=[work.faces[index] for index in sorted(faces)], context="FACES")
    work.to_mesh(obj.data)
    work.free()
    obj.data.update()


def place(obj):
    """Stands the ore on its foot at the origin and sizes its longest side to SIZE. Returns the
    scale."""
    mesh = obj.data
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    low, high = points.min(axis=0), points.max(axis=0)
    mesh.transform(Matrix.Translation((-(low[0] + high[0]) / 2.0, -(low[1] + high[1]) / 2.0, -low[2])))
    size = SIZE / float((high - low).max())
    mesh.transform(Matrix.Scale(size, 4))
    mesh.update()
    return size


def vertex_data(mesh):
    """Each vertex's position and normal, the normal summed here in a fixed order (lib/fixed_order.py):
    Blender's own differs with the thread count, and the paint's cuts would follow it."""
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            fixed_order.vertex_normals(mesh, angle=True))


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    ore = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    ore.name = ore.data.name = "CopperRibbonsOre"
    scene.select_only(ore)
    # The source's normals come back as custom ones, which sort_mesh refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    weld(ore)

    # The owner's fix: the ribbon that leaves the stone as two strands goes, whole.
    piece_of, ribbons, split = ribbons_and_split(ore.data)
    gone = [face for face, number in piece_of.items() if number == split]
    remove(ore, gone)
    piece_of = repaint.pieces(ore.data)
    stone_pieces = {number for face, number in piece_of.items()
                    if min(ore.data.vertices[index].co.z for index in ore.data.polygons[face].vertices)
                    <= min(vertex.co.z for vertex in ore.data.vertices) + GROUND}

    size = place(ore)
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    mesh = ore.data
    # Only the set's materials, in their slots, whatever the download carried.
    mesh.materials.clear()
    mesh.materials.append(prop_paint.material("stone", "stone"))
    mesh.materials.append(prop_paint.material("stone_shaded", "stone", prop_paint.Weathering.shade))
    mesh.materials.append(prop_paint.flat("copper", COPPER))
    for polygon in mesh.polygons:
        polygon.material_index = STONE if piece_of[polygon.index] in stone_pieces else RIBBONS

    # The shaded step: the joins between the chunks and the foot, on the stone only.
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(ore, points, normals, REACH)
    dark = prop_paint.contour(mesh, prop_paint.darkness(points, shut), prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        if above and polygon.material_index == STONE:
            polygon.material_index = SHADED
    prop_paint.box_uv(mesh)

    points, _normals = vertex_data(mesh)
    counts = numpy.bincount([polygon.material_index for polygon in mesh.polygons], minlength=len(mesh.materials))
    print("REMOVED split ribbon: %d of the source's faces; %d ribbons left, %d stone pieces"
          % (len(gone), len(ribbons) - 1, len(stone_pieces)))
    print("BUDGET triangles", scene.triangles(ore), "materials", len(mesh.materials),
          "textures %dx%d" % tuple(bpy.data.images["stone"].size), "scale %.4f" % size,
          "size %.3f x %.3f x %.3f" % tuple((points.max(axis=0) - points.min(axis=0)).tolist()),
          "faces per material", dict(zip([m.name for m in mesh.materials], counts.tolist())))
    scene.export_glb(out)


main()
