"""The ore outcrop (#1929): a boulder of broken stone with copper running through its cracks, the ore
source in the mountains (the copper ore tile). Its shape is the owner's generated model, made
without a texture (`sources/ore_outcrop.glb`, from the download by import_source.py: see the
asset's SOURCE.md); its colours are the props' shared stone (lib/prop_paint.py, CC0 textures) with
a darker shaded step, and the veins, the deep cracks between its chunks, as a material of their own,
one flat copper tint (`prop_paint.flat`): another ore (iron, crystal) is this shape with another
colour on its veins (retexture first, #1847). No moss, so the veins read from the camera, and no
runes or writing (the owner, on #1929). A static model: no rig and no clips.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/ore_outcrop.py -- packages/game/assets/ore-outcrop/ore_outcrop.glb

Blender is Z-up; the origin is at the boulder's foot, in the middle of its hex, and it is sized to
its hex as a prop (lib/footprint.py's `PROP`)."""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import footprint, prop_paint, scene  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "ore_outcrop.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a thing standing on one hex.
WORLD_SCALE = "prop"
# Edges sharper than this stay sharp in the shading: the chunks' broken facets.
SHARP = math.radians(40.0)
# The veins' colour: copper, as a flat tint (sRGB).
VEIN_COLOUR = (0.86, 0.50, 0.22)
# The materials, in their slots.
STONE, SHADED, VEINS = range(3)
# How far a crack's darkness looks, in metres once sized: short, so only the narrow cracks between
# the chunks are shut in, not the wide hollows.
REACH = 0.08
# A vertex shut in past this lies in a crack: a vein.
VEIN = 0.42


def place(obj):
    """Stands the boulder on the ground at the hex's centre and sizes it to its hex as a prop.
    Returns the scale."""
    mesh = obj.data
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    low, high = points.min(axis=0), points.max(axis=0)
    mesh.transform(Matrix.Translation((-(low[0] + high[0]) / 2.0, -(low[1] + high[1]) / 2.0, -low[2])))
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    size = footprint.SLACK * footprint.PROP[0] / footprint.spread(points)
    mesh.transform(Matrix.Scale(size, 4))
    mesh.update()
    return size


def weld(obj):
    """Joins the seam splits by position, so the surface shades whole, not island by island (the
    starry egg's trap, model skill)."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    bmesh.ops.remove_doubles(work, verts=work.verts, dist=1e-5)
    work.to_mesh(obj.data)
    work.free()


def vertex_data(mesh):
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            numpy.array([vertex.normal[:] for vertex in mesh.vertices]))


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    rock = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    rock.name = rock.data.name = "OreOutcrop"
    scene.select_only(rock)
    # The source's normals come back as custom ones, which sort_mesh refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    weld(rock)
    size = place(rock)
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    mesh = rock.data
    # Only the set's materials, in their slots, whatever the download carried.
    mesh.materials.clear()
    mesh.materials.append(prop_paint.material("stone", "stone"))
    mesh.materials.append(prop_paint.material("stone_shaded", "stone", prop_paint.Weathering.shade))
    mesh.materials.append(prop_paint.flat("veins", VEIN_COLOUR))

    # The veins: the cracks, cut along their edge so each is a clean flat band.
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(rock, points, normals, REACH)
    veins = prop_paint.contour(mesh, shut, VEIN)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, veins, VEIN)):
        polygon.material_index = VEINS if above else STONE

    # The shaded step: the wider hollows and the foot, on the stone only.
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(rock, points, normals, 2.0 * REACH)
    dark = prop_paint.contour(mesh, prop_paint.darkness(points, shut), prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        if above and polygon.material_index == STONE:
            polygon.material_index = SHADED
    prop_paint.box_uv(mesh)

    points, _normals = vertex_data(mesh)
    counts = numpy.bincount([polygon.material_index for polygon in mesh.polygons], minlength=len(mesh.materials))
    print("BUDGET triangles", scene.triangles(rock), "materials", len(mesh.materials),
          "textures %dx%d" % tuple(bpy.data.images["stone"].size), "scale %.4f" % size,
          "height %.3f" % points[:, 2].max(), "faces per material", dict(zip([m.name for m in mesh.materials], counts.tolist())),
          "reach %.3f" % footprint.spread(points))
    scene.export_glb(out)


main()
