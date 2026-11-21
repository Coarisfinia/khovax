"""The savanna tree (#1999): a winding trunk forking into bare branches under a wide, flat crown of
rounded leaf masses. Its shape is the owner's generated model, made without a texture
(`source.glb` beside this script, from the download by import_source.py: see the asset's
SOURCE.md). This script cleans it and paints it:

- **the canopy's outcrops go**: the generator scattered many small leaf lumps on and around the
  main rounded leaf masses, which break the crown's calm silhouette. Each is a loose piece of its
  own, far smaller than any leaf mass, so every crown piece under `OUTCROP_FACES` faces is
  dropped here, never in the raw export (the owner, on #1999);
- **trunk and crown are separate parts**: `Trunk` (the trunk, its branches and its roots) and
  `Crown` (the leaf masses), so the game hides the crown alone when a figure stands under it
  (CanopyCutaway, #1999) and the footprint check holds the trunk to its hex while the crown may
  overhang its neighbours (check_footprint.py). The crown's origin is at its underside's middle,
  so scaling it shrinks it onto the branches;
- **its colours**: the trunk from the props' shared texture set (lib/prop_paint.py: wood, a
  shaded step in its crevices and at its foot), the crown in our own flat foliage greens, a
  darker step on the leaf masses' undersides.

A static model: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python resourcepacks/default/models/savanna-tree/build/savanna_tree.py -- resourcepacks/default/models/savanna-tree/savanna_tree.glb

Blender is Z-up and the tree faces -Y (the game's +Z); the origin is at the trunk's foot, in the
middle of its hex. It is built at the size the game draws it (its tile blueprint's scale makes
TileDecorations' shrink 1)."""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
# The model library, src/game-models/lib/, from this model's build folder (#2438).
sys.path.insert(0, os.path.normpath(os.path.join(HERE, *[os.pardir] * 5, "src", "game-models")))

from lib import fixed_order, footprint, prop_paint, repaint, scene, world_scale  # noqa: E402

SOURCE = os.path.join(HERE, "source.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a thing standing on one hex. Only its trunk
# stands on it; the crown overhangs (check_footprint.py).
WORLD_SCALE = "prop"
# How tall it stands, in metres: above the player, so its crown spreads over their head.
HEIGHT = 1.3 * world_scale.PLAYER_HEIGHT
# Edges sharper than this stay sharp in the shading: the leaf masses' facets.
SHARP = math.radians(40.0)
# A crown piece with fewer faces than this is an outcrop, dropped: the source's leaf masses have
# 76 faces and more, its outcrops 26 and fewer.
OUTCROP_FACES = 40
# A piece starting above this share of the tree's height is a leaf mass; below are the trunk's
# roots (the trunk itself, with its branches, is the largest piece).
CROWN_FROM = 0.5
# Where the trunk forks, as a share of the tree's height: below it the stem stands within its hex,
# above it the branches spread under the leaf masses, so they're the crown's.
FORK = 0.56
# The parts' names, which the game finds the crown by (CanopyCutaway.CROWN).
TRUNK, CROWN = "Trunk", "Crown"
# The materials, in their slots: the trunk's from the set, the crown's our own flat greens (sRGB).
BARK, BARK_SHADED, FOLIAGE, FOLIAGE_SHADED = range(4)
FOLIAGE_COLOUR = (0.42, 0.55, 0.22)
FOLIAGE_SHADED_COLOUR = (0.27, 0.40, 0.16)
# How far a crevice's darkness looks on the trunk, in metres.
REACH = 0.25
# A leaf face is in the darker step where its normal's upward share is below this, give or take
# the wobble.
FOLIAGE_UP = -0.1
FOLIAGE_WOBBLE = 0.15
FOLIAGE_SIZE = 0.12


def place(obj, pieces):
    """Stands the tree on the ground with its trunk's foot at the hex's centre and sizes it to
    `HEIGHT`. Returns the scale."""
    mesh = obj.data
    points = numpy.array([vertex.co[:] for vertex in mesh.vertices])
    low = points[:, 2].min()
    # The foot: the trunk's and roots' vertices near the ground, whose middle the hex's centre is.
    trunk = numpy.zeros(len(points), dtype=bool)
    for polygon in mesh.polygons:
        if pieces[polygon.index] == 0:
            trunk[list(polygon.vertices)] = True
    foot = points[trunk & (points[:, 2] < low + 0.02 * (points[:, 2].max() - low))]
    middle = (foot.min(axis=0) + foot.max(axis=0)) / 2.0
    mesh.transform(Matrix.Translation((-middle[0], -middle[1], -low)))
    size = HEIGHT / (points[:, 2].max() - low)
    mesh.transform(Matrix.Scale(size, 4))
    mesh.update()
    return size


def drop_outcrops(obj):
    """Deletes the crown's outcrops (see the module's notes) and returns how many. The pieces are
    numbered by size, so a small piece low down (a root) is told apart by its height."""
    mesh = obj.data
    pieces = repaint.pieces(mesh)
    top = max(vertex.co.z for vertex in mesh.vertices)
    faces = {}
    for polygon in mesh.polygons:
        faces.setdefault(pieces[polygon.index], []).append(polygon)
    dropped = []
    for piece, polygons in sorted(faces.items()):
        lowest = min(mesh.vertices[index].co.z for polygon in polygons for index in polygon.vertices)
        if piece != 0 and lowest > CROWN_FROM * top and len(polygons) < OUTCROP_FACES:
            dropped.append(piece)
    work = bmesh.new()
    work.from_mesh(mesh)
    work.faces.ensure_lookup_table()
    gone = [work.faces[polygon.index] for piece in dropped for polygon in faces[piece]]
    bmesh.ops.delete(work, geom=gone, context="FACES")
    work.to_mesh(mesh)
    work.free()
    mesh.update()
    return len(dropped)


def part(obj, name, keep):
    """A copy of `obj` named `name`, keeping only the faces `keep` (face index to bool) says."""
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(copy)
    work = bmesh.new()
    work.from_mesh(copy.data)
    work.faces.ensure_lookup_table()
    bmesh.ops.delete(work, geom=[face for face in work.faces if not keep[face.index]], context="FACES")
    work.to_mesh(copy.data)
    work.free()
    copy.name = copy.data.name = name
    return copy


def cut(obj, height, keep_below):
    """Cuts `obj` at `height`, keeping what lies below it or above it, the cut capped flat."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    fixed_order.cut(work, Vector((0.0, 0.0, height)), Vector((0.0, 0.0, 1.0 if keep_below else -1.0)))
    work.to_mesh(obj.data)
    work.free()
    obj.data.update()


def split(obj):
    """Splits the tree at `FORK` into its trunk (the stem below it and the roots) and the parts
    above it, the branches (the rest of the largest piece) and the leaf masses (the other pieces
    up there). Returns (trunk, branches, leaves)."""
    mesh = obj.data
    pieces = repaint.pieces(mesh)
    top = max(vertex.co.z for vertex in mesh.vertices)
    lowest = {}
    for polygon in mesh.polygons:
        z = min(mesh.vertices[index].co.z for index in polygon.vertices)
        lowest[pieces[polygon.index]] = min(lowest.get(pieces[polygon.index], z), z)
    in_crown = {piece for piece, z in lowest.items() if piece != 0 and z > CROWN_FROM * top}
    fork = FORK * top
    trunk = part(obj, TRUNK, {face: piece not in in_crown for face, piece in pieces.items()})
    cut(trunk, fork, True)
    branches = part(obj, "Branches", {face: piece == 0 for face, piece in pieces.items()})
    cut(branches, fork, False)
    leaves = part(obj, "Leaves", {face: piece in in_crown for face, piece in pieces.items()})
    bpy.data.objects.remove(obj)
    return trunk, branches, leaves


def join(branches, leaves):
    """The crown: the branches and the leaf masses as one part, its origin in the middle of the
    cut at `FORK`, so the game scales it down into the trunk's top."""
    points = numpy.array([vertex.co[:] for vertex in branches.data.vertices])
    seam = points[numpy.abs(points[:, 2] - points[:, 2].min()) < 1e-4]
    origin = Vector(((seam[:, 0].min() + seam[:, 0].max()) / 2.0, (seam[:, 1].min() + seam[:, 1].max()) / 2.0,
                     points[:, 2].min()))
    for obj in (branches, leaves):
        obj.data.transform(Matrix.Translation(-origin))
    bpy.ops.object.select_all(action="DESELECT")
    leaves.select_set(True)
    branches.select_set(True)
    bpy.context.view_layer.objects.active = branches
    bpy.ops.object.join()
    branches.name = branches.data.name = CROWN
    branches.location = origin
    bpy.context.view_layer.update()
    return branches


def vertex_data(mesh):
    """Each vertex's position and normal, the normal summed here in a fixed order (lib/fixed_order.py):
    Blender's own differs with the thread count, and the paint's cuts would follow it."""
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            fixed_order.vertex_normals(mesh, angle=True))


def paint_bark(obj, materials):
    """The trunk's or the branches' wood, darker in its crevices and at the trunk's foot."""
    mesh = obj.data
    for material in materials:
        mesh.materials.append(material)
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(obj, points, normals, REACH)
    dark = prop_paint.contour(mesh, prop_paint.darkness(points, shut), prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        polygon.material_index = BARK_SHADED if above else BARK
    prop_paint.box_uv(mesh)


def paint_leaves(leaves, materials):
    """The leaf masses' foliage, a darker step on their undersides, its edge wobbling."""
    mesh = leaves.data
    for material in materials:
        mesh.materials.append(material)
    points, normals = vertex_data(mesh)
    lit = normals[:, 2] - FOLIAGE_UP + FOLIAGE_WOBBLE * prop_paint.noise(points, FOLIAGE_SIZE, prop_paint.Weathering.seed + 7)
    lit = prop_paint.contour(mesh, lit, 0.0)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, lit, 0.0)):
        polygon.material_index = FOLIAGE if above else FOLIAGE_SHADED


def world_points(obj):
    return numpy.array([(obj.matrix_world @ vertex.co)[:] for vertex in obj.data.vertices])


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    tree = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    scene.select_only(tree)
    # The source's normals come back as custom ones, which sort_mesh refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    size = place(tree, repaint.pieces(tree.data))
    outcrops = drop_outcrops(tree)
    trunk, branches, leaves = split(tree)
    for obj in (trunk, branches, leaves):
        scene.select_only(obj)
        bpy.ops.object.shade_smooth_by_angle(angle=SHARP)

    materials = [prop_paint.material("bark", "wood"),
                 prop_paint.material("bark_shaded", "wood", prop_paint.Weathering.shade),
                 prop_paint.flat("foliage", FOLIAGE_COLOUR), prop_paint.flat("foliage_shaded", FOLIAGE_SHADED_COLOUR)]
    # Every part's slots hold every material in the same order, so the indices mean the same on all.
    paint_bark(trunk, materials)
    paint_bark(branches, materials)
    paint_leaves(leaves, materials)
    crown = join(branches, leaves)

    trunk_points, crown_points = world_points(trunk), world_points(crown)
    # The crown's lowest point over the neighbours, which the tile blueprint's clearance names.
    beyond = crown_points[numpy.array([footprint.spread(point[None, :]) > 1.0 for point in crown_points])]
    print("BUDGET triangles trunk", scene.triangles(trunk), "crown", scene.triangles(crown),
          "materials", len(materials), "textures %dx%d" % tuple(bpy.data.images["wood"].size),
          "scale %.4f" % size, "outcrops dropped", outcrops,
          "height %.3f" % max(trunk_points[:, 2].max(), crown_points[:, 2].max()))
    print("REACH trunk %.3f crown %.3f of the hex; the crown over the neighbours from %.3f m"
          % (footprint.spread(trunk_points), footprint.spread(crown_points), beyond[:, 2].min()))
    scene.export_glb(out)


main()
