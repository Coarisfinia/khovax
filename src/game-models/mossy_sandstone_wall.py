"""The mossy sandstone wall (#1832, from #1824): a wall piece of pillowy sandstone blocks in courses,
the wall the fliers' realm (#1834) and the buildings (#1835) are built from. Its shape is the owner's
generated model (`sources/mossy_sandstone_wall.glb`, from the download by import_source.py: see the
asset's SOURCE.md); its colours are the props' shared texture set (lib/prop_paint.py, CC0
textures), mapped by this script: sandstone, moss on its top and ledges, darker joints and foot.
The download's own paint (a patchwork that broke at the ends and the back) is dropped with it. A
static model: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python src/game-models/mossy_sandstone_wall.py -- resourcepacks/default/models/mossy-sandstone-wall/mossy_sandstone_wall.glb

It's a wall on the world's scale (lib/world_scale.py, #1837): an edge piece along Blender's X,
centred on the origin at the edge's middle, `HEX_EDGE` long and `WALL_HEIGHT` tall, its ends cut
flat so pieces meet end to end at a hex's corners (a corner tower, #1836, covers the joint later).
The download is a long, low wall, three times as long as it is tall, while a wall piece on one edge
is far taller than long. So the script stacks `COURSES` windows of it, each cut flat at both ends
and at its foot (where the download's strip of grass was: the ground is ours), each from another
stretch of the download so the joints don't line up, until the stack stands a wall's height; the
blocks keep their shape, scaled alike in every direction.

Blender is Z-up and the wall's face looks along -Y (the game's +Z); the origin is at its foot."""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import prop_paint, scene, world_scale  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "mossy_sandstone_wall.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a wall piece along one hex edge.
WORLD_SCALE = "wall"
# Edges sharper than this stay sharp in the shading: the blocks' corners and the cut ends.
SHARP = math.radians(40.0)

# In the download's own units: the top of its strip of grass, where each window is cut at its foot.
GRASS_TOP = -0.127
# The stretches of the download stacked from the foot up, each by where it starts along X; each is
# the download's length over the scale long, so it spans the edge once sized.
WINDOWS = (-0.40, 0.12, -0.16)
# How far each window sinks into the rounded tops of the one below (download units), so no gap
# shows between them.
SINK = 0.008
# The materials, in their slots: (name, the set's texture, its grey factor).
MATERIALS = (("sandstone", "sandstone", 1.0),
             ("sandstone_shaded", "sandstone", prop_paint.Weathering.shade),
             ("moss", "moss", 1.0))
SANDSTONE, SHADED, MOSS = range(3)
# How far a joint's darkness looks, in metres once sized.
REACH = 0.1
# The paint's values are rounded to this many decimals before the cuts, and the wall's vertices to
# one more (metres): another machine's numpy and Blender differ in the last bits, which would move a
# cut or reorder the export, so CI's build would differ from the committed one (check_rebuild.py).
DECIMALS = 4


def weld(work):
    """Joins the seam splits by position, so the surface shades whole, not island by island. By
    hand rather than with `remove_doubles`, whose search runs on several threads and picks other
    survivors with another thread count (CI's rebuild then differs)."""
    first = {}
    targets = {}
    for vert in work.verts:
        key = tuple(round(value, 5) for value in vert.co)
        if key in first:
            targets[vert] = first[key]
        else:
            first[key] = vert
    bmesh.ops.weld_verts(work, targetmap=targets)


def canonical(work):
    """Rebuilds `work` in a fixed order: its vertices by position (on a fine grid, download units),
    its faces by their vertices, each starting at its lowest one. bisect_plane hands back faces in
    an order, and starting at a corner, that change with the thread count, and the next step's
    choices (a cap's triangles) follow them, so CI's rebuild would differ from the committed file;
    from a fixed order every step comes out alike."""
    points = sorted({tuple(round(value, 6) for value in vert.co) for vert in work.verts})
    index = {point: place for place, point in enumerate(points)}
    faces = set()
    for face in work.faces:
        ring = [index[tuple(round(value, 6) for value in vert.co)] for vert in face.verts]
        # A sliver whose corners met on the grid is dropped.
        ring = [place for step, place in enumerate(ring) if place != ring[step - 1]]
        if len(set(ring)) < 3 or len(set(ring)) != len(ring):
            continue
        start = ring.index(min(ring))
        faces.add(tuple(ring[start:] + ring[:start]))
    work.clear()
    verts = [work.verts.new(point) for point in points]
    for face in sorted(faces):
        work.faces.new([verts[place] for place in face])
    work.verts.index_update()
    work.faces.index_update()


def cut(work, point, normal):
    """Cuts `work` at the plane through `point`, keeping the side `normal` points away from, and
    closes the cut with flat faces."""
    canonical(work)
    bmesh.ops.bisect_plane(work, geom=work.verts[:] + work.edges[:] + work.faces[:], dist=1e-6,
                           plane_co=point, plane_no=normal, clear_outer=True)
    canonical(work)
    filled = bmesh.ops.holes_fill(work, edges=[edge for edge in work.edges if edge.is_boundary])
    # Ear clipping, not "beauty": a flat cap's beauty flips hang on ties between equal angles.
    bmesh.ops.triangulate(work, faces=filled["faces"], quad_method="FIXED", ngon_method="EAR_CLIP")
    canonical(work)


def scale_and_length(source_mesh):
    """The scale that makes the stacked windows a wall's height, and each window's length in the
    download's units (an edge's at that scale)."""
    top = max(vertex.co.z for vertex in source_mesh.vertices)
    tall = len(WINDOWS) * (top - GRASS_TOP) - (len(WINDOWS) - 1) * SINK
    size = world_scale.WALL_HEIGHT / tall
    return size, world_scale.HEX_EDGE / size, top


def window(source_mesh, start, length):
    """The download's stretch from `start` along X, `length` long, cut flat at both ends and at the
    grass's top, moved so its foot is at z 0 and its middle at x 0 (download units)."""
    work = bmesh.new()
    work.from_mesh(source_mesh)
    weld(work)
    cut(work, Vector((start, 0.0, 0.0)), Vector((-1.0, 0.0, 0.0)))
    cut(work, Vector((start + length, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)))
    cut(work, Vector((0.0, 0.0, GRASS_TOP)), Vector((0.0, 0.0, -1.0)))
    bmesh.ops.translate(work, verts=work.verts, vec=Vector((-(start + length / 2.0), 0.0, -GRASS_TOP)))
    return work


def build(source):
    """The wall: the windows stacked and sized, as one mesh object."""
    size, length, top = scale_and_length(source.data)
    if WINDOWS and (min(WINDOWS) < min(v.co.x for v in source.data.vertices)
                    or max(WINDOWS) + length > max(v.co.x for v in source.data.vertices)):
        raise SystemExit("a window reaches past the download's ends")
    stack = bmesh.new()
    rise = 0.0
    for start in WINDOWS:
        work = window(source.data, start, length)
        bmesh.ops.translate(work, verts=work.verts, vec=Vector((0.0, 0.0, rise)))
        piece = bpy.data.meshes.new("window")
        work.to_mesh(piece)
        work.free()
        stack.from_mesh(piece)
        bpy.data.meshes.remove(piece)
        rise += (top - GRASS_TOP) - SINK
    bmesh.ops.scale(stack, verts=stack.verts, vec=Vector((size, size, size)))
    # The cuts' vertices land a last bit apart on another machine (its float maths), which reorders
    # the sorted export; on a fine grid they land alike, the flat ends exactly at the edge's ends.
    for vert in stack.verts:
        vert.co = Vector([round(value, DECIMALS + 1) for value in vert.co])
    canonical(stack)
    mesh = bpy.data.meshes.new("MossySandstoneWall")
    stack.to_mesh(mesh)
    stack.free()
    wall = bpy.data.objects.new("MossySandstoneWall", mesh)
    bpy.context.scene.collection.objects.link(wall)
    bpy.data.objects.remove(source)
    return wall, size


def snap(mesh):
    """Puts every vertex of `mesh` on a grid of `DECIMALS + 1` decimals (metres): a cut's vertex
    lands a last bit apart on another machine (its float maths), which reorders the sorted export."""
    points = numpy.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", points)
    mesh.vertices.foreach_set("co", numpy.round(points, DECIMALS + 1))
    mesh.update()


def vertex_data(mesh):
    """Each vertex's position and normal. The normal is summed from its faces' here, in their
    order: Blender sums them on several threads, which leaves last bits that change with the
    thread count, and the paint's cuts would follow them (CI's rebuild then differs)."""
    normals = numpy.zeros((len(mesh.vertices), 3))
    for polygon in mesh.polygons:
        weighted = numpy.array(polygon.normal[:]) * polygon.area
        for index in polygon.vertices:
            normals[index] += weighted
    lengths = numpy.linalg.norm(normals, axis=1, keepdims=True)
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            numpy.round(normals / numpy.maximum(lengths, 1e-12), DECIMALS + 2))


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    source = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    for obj in list(bpy.context.scene.objects):
        if obj is not source:
            bpy.data.objects.remove(obj)
    scene.select_only(source)
    # The source's normals come back as custom ones, which sort_mesh refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    source.data.transform(source.matrix_world)
    source.matrix_world = Matrix.Identity(4)
    wall, size = build(source)
    scene.select_only(wall)
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    mesh = wall.data
    # Only the set's materials, in their slots, whatever the download carried.
    mesh.materials.clear()
    for name, texture, factor in MATERIALS:
        mesh.materials.append(prop_paint.material(name, texture, factor))

    # Moss on the blocks' tops and ledges, cut along its edge.
    points, normals = vertex_data(mesh)
    moss = prop_paint.contour(mesh, numpy.round(prop_paint.mossiness(points, normals), DECIMALS), 0.0)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, moss, 0.0)):
        polygon.material_index = MOSS if above else SANDSTONE

    # The shaded step: the joints between the blocks, and the foot.
    points, normals = vertex_data(mesh)
    shut = prop_paint.occlusion(wall, points, normals, REACH)
    dark = prop_paint.contour(mesh, numpy.round(prop_paint.darkness(points, shut), DECIMALS),
                            prop_paint.Weathering.shaded)
    for polygon, above in zip(mesh.polygons, prop_paint.side(mesh, dark, prop_paint.Weathering.shaded)):
        if above and polygon.material_index == SANDSTONE:
            polygon.material_index = SHADED
    # The cuts' new vertices too, onto the grid (see `snap`) before the UVs are laid from them.
    snap(mesh)
    prop_paint.box_uv(mesh)

    points, _normals = vertex_data(mesh)
    length, height = world_scale.bounds(points)
    counts = numpy.bincount([polygon.material_index for polygon in mesh.polygons], minlength=len(mesh.materials))
    print("BUDGET triangles", scene.triangles(wall), "materials", len(mesh.materials),
          "textures %dx%d" % tuple(bpy.data.images["sandstone"].size), "scale %.4f" % size,
          "length %.3f" % length, "height %.3f" % height, "depth %.3f" % (points[:, 1].max() - points[:, 1].min()),
          "faces per material", dict(zip([m.name for m in mesh.materials], counts.tolist())))
    scene.export_glb(out)


main()
