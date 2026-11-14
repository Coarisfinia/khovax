"""The ranch feeding trough (#2387): a long wooden box on four short legs, a world prop at the ranch.
Its shape is the owner's generated model, made without a texture (`sources/ranch_feeding_trough.glb`,
from the download by import_source.py: see the asset's SOURCE.md); its colours are the props'
shared wood (lib/prop_paint.py, CC0 textures), mapped by this script: the planks, a darker shaded
step in the joints and at the legs' foot, and the trough's inside (its floor and inner walls) as a
part of its own, `basin`, so what it holds (feed, water) can be painted there later without
touching the planks. No runes or writing. A static model: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/ranch_feeding_trough.py -- \
        resourcepacks/default/models/ranch-feeding-trough/ranch_feeding_trough.glb

Blender is Z-up; the trough runs along X, its long side facing -Y (the game's +Z); the origin is
at its feet, in the middle of its hex, and it is sized to its hex as a prop (lib/footprint.py's
`PROP`)."""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import fixed_order, footprint, prop_paint, scene  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "ranch_feeding_trough.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a thing standing on one hex.
WORLD_SCALE = "prop"
# Edges sharper than this stay sharp in the shading: the planks' corners.
SHARP = math.radians(40.0)
# The basin in the source's own units (before placing and sizing): the inner walls stand at about
# x = ±0.37 and y = ±0.19..0.24, the floor at z = 0 and the rim at z = 0.16. A face whose centre
# lies inside this box, above the floor's underside, and that faces up or in, is the basin's.
BASIN_X, BASIN_Y, BASIN_FLOOR = 0.385, 0.245, -0.03
# How far a face must turn up or toward the trough's middle to be the basin's (its normal's share).
INWARD = 0.3
# The basin's darker wood (linear factor): the inside lies in its own shadow, so it reads as a
# hollow from the top-down camera.
BASIN_SHADE = 0.6
# The materials, in their slots.
WOOD, SHADED, BASIN = range(3)
# How far a joint's darkness looks, in metres once sized: short, so only the gaps between planks.
REACH = 0.08


def place(obj):
    """Stands the trough on the ground at the hex's centre and sizes it to its hex as a prop.
    Returns the scale and the shift applied before it."""
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


def weld(obj):
    """Joins the seam splits by position, so the surface shades whole, not island by island (the
    starry egg's trap, model skill), in a fixed order (lib/fixed_order.py)."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    fixed_order.weld(work)
    work.to_mesh(obj.data)
    work.free()


def vertex_data(mesh):
    """Each vertex's position and normal, the normal summed here in a fixed order (lib/fixed_order.py):
    Blender's own differs with the thread count, and the paint's cuts would follow it."""
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            fixed_order.vertex_normals(mesh, angle=True))


def basin_faces(mesh, size, shift):
    """Whether each face is the basin's: inside the inner walls, above the floor's underside, and
    turned up or toward the trough's middle (so the walls' outer faces and the floor's underside
    stay planks)."""
    inside = []
    for polygon in mesh.polygons:
        normal = polygon.normal
        # The face's centre back in the source's units, where the box is measured.
        centre = polygon.center / size - shift.translation
        within = abs(centre.x) < BASIN_X and abs(centre.y) < BASIN_Y and centre.z > BASIN_FLOOR
        inward = max(normal.z, -math.copysign(1.0, centre.x) * normal.x, -math.copysign(1.0, centre.y) * normal.y)
        inside.append(within and inward > INWARD)
    return inside


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    trough = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    trough.name = trough.data.name = "RanchFeedingTrough"
    scene.select_only(trough)
    # The source's normals come back as custom ones, which sort_mesh refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    weld(trough)
    size, shift = place(trough)
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    mesh = trough.data
    # Only the set's materials, in their slots, whatever the download carried.
    mesh.materials.clear()
    mesh.materials.append(prop_paint.material("wood", "wood"))
    mesh.materials.append(prop_paint.material("wood_shaded", "wood", prop_paint.Weathering.shade))
    mesh.materials.append(prop_paint.material("basin", "wood", BASIN_SHADE))

    # The shaded step: the joints between planks and the legs' foot, cut along its edge so it is a
    # clean flat band.
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(trough, points, normals, REACH)
    dark = prop_paint.contour(mesh, prop_paint.darkness(points, shut), prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        polygon.material_index = SHADED if above else WOOD

    # The basin, its own part whatever the shading found there.
    for polygon, inside in zip(mesh.polygons, basin_faces(mesh, size, shift)):
        if inside:
            polygon.material_index = BASIN
    prop_paint.box_uv(mesh)

    points, _normals = vertex_data(mesh)
    counts = numpy.bincount([polygon.material_index for polygon in mesh.polygons], minlength=len(mesh.materials))
    print("BUDGET triangles", scene.triangles(trough), "materials", len(mesh.materials),
          "textures %dx%d" % tuple(bpy.data.images["wood"].size), "scale %.4f" % size,
          "length %.3f" % (points[:, 0].max() - points[:, 0].min()),
          "depth %.3f" % (points[:, 1].max() - points[:, 1].min()),
          "height %.3f" % points[:, 2].max(), "faces per material", dict(zip([m.name for m in mesh.materials], counts.tolist())),
          "reach %.3f" % footprint.spread(points))
    scene.export_glb(out)


main()
