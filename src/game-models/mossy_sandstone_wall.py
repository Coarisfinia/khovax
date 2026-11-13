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
    """Joins the seam splits by position, so the surface shades whole, not island by island."""
    bmesh.ops.remove_doubles(work, verts=work.verts, dist=1e-5)


def cut(work, point, normal):
    """Cuts `work` at the plane through `point`, keeping the side `normal` points away from, and
    closes the cut with flat faces."""
    geom = work.verts[:] + work.edges[:] + work.faces[:]
    result = bmesh.ops.bisect_plane(work, geom=geom, dist=1e-6, plane_co=point, plane_no=normal,
                                    clear_outer=True)
    edges = [element for element in result["geom_cut"] if isinstance(element, bmesh.types.BMEdge)]
    filled = bmesh.ops.holes_fill(work, edges=[edge for edge in edges if edge.is_valid and edge.is_boundary])
    bmesh.ops.triangulate(work, faces=filled["faces"], quad_method="BEAUTY", ngon_method="BEAUTY")


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
    mesh = bpy.data.meshes.new("MossySandstoneWall")
    stack.to_mesh(mesh)
    stack.free()
    wall = bpy.data.objects.new("MossySandstoneWall", mesh)
    bpy.context.scene.collection.objects.link(wall)
    bpy.data.objects.remove(source)
    return wall, size


def vertex_data(mesh):
    return (numpy.array([vertex.co[:] for vertex in mesh.vertices]),
            numpy.array([vertex.normal[:] for vertex in mesh.vertices]))


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
