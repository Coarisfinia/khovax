"""Imports the player's body (#1827): the baseline body as Meshy rigged it, with the texture of the
textured export of the same body, as the figure PlayerView shows.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/import_body.py -- <rigged.glb> <textured.glb> <body.glb> [size=1024]

Meshy rigged the untextured body and textured it apart, so the rigged export has no UVs and the
textured one no rig. They are the same triangles, the textured one at another size and place, so
each corner of the rigged body takes its UV from the same corner of the textured one, matched by
position: the texture fits the rig exactly, with nothing baked or resampled. It fails, naming how
far off, when a triangle has no twin there: then the two meshes differ and the texture can't be
moved over.

The body keeps Meshy's rig as it is, bones and rest pose (no clips: the player's clip library,
player_clips.glb, holds them, on the same skeleton, sources/player/skeleton.glb, which this
checks), and only the base colour of the texture, shrunk to `size`, opaque, single-sided and
matte (lib/source_material.py). Its corners split by the rig's export are welded by position, so
the toon look shades it smooth."""

import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import skeleton, source_material  # noqa: E402

# How far a twin's corner may lie from the rigged body's, in metres at the rigged body's size:
# float noise from Meshy's two exports, far below the smallest triangle.
TWIN = 1e-4
# Corners of the rigged body closer than this are one vertex (the export split every triangle).
WELD = 1e-5
# The colour's JPEG quality, as import_source.py's.
QUALITY = 90
SKELETON = os.path.join(HERE, "sources", "player", "skeleton.glb")


def load(path):
    """The objects the .glb at `path` adds to the scene."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [obj for obj in bpy.data.objects if obj not in before]


def corners(obj):
    """Every triangle of `obj` in world space: its corners' positions and loop indices."""
    matrix = obj.matrix_world
    mesh = obj.data
    if any(len(polygon.vertices) != 3 for polygon in mesh.polygons):
        raise RuntimeError("%s has faces that aren't triangles" % obj.name)
    return [[(matrix @ mesh.vertices[mesh.loops[loop].vertex_index].co, loop) for loop in polygon.loop_indices]
            for polygon in mesh.polygons]


def bounds(triangles):
    points = [point for triangle in triangles for point, _loop in triangle]
    low = Vector([min(point[axis] for point in points) for axis in range(3)])
    high = Vector([max(point[axis] for point in points) for axis in range(3)])
    return low, high


def transfer(body, textured):
    """Gives each corner of `body` the UV of its twin on `textured`, the same triangle at another
    size and place, and returns how far the farthest twin lay."""
    ours, theirs = corners(body), corners(textured)
    if len(ours) != len(theirs):
        raise RuntimeError("the rigged body has %d triangles, the textured %d: not the same mesh"
                           % (len(ours), len(theirs)))
    (low, high), (their_low, their_high) = bounds(ours), bounds(theirs)
    # One scale for all three axes, from the height: the textured body is the rigged one resized.
    scale = (high.z - low.z) / (their_high.z - their_low.z)

    def placed(point):
        return (point - their_low) * scale + low

    uvs = textured.data.uv_layers.active.data
    tree = KDTree(len(theirs))
    for index, triangle in enumerate(theirs):
        tree.insert(sum((placed(point) for point, _loop in triangle), Vector()) / 3.0, index)
    tree.balance()
    layer = body.data.uv_layers.new(name="UVMap")
    farthest, twins = 0.0, set()
    for triangle in ours:
        centre = sum((point for point, _loop in triangle), Vector()) / 3.0
        _found, index, _distance = tree.find(centre)
        twins.add(index)
        for point, loop in triangle:
            their_point, their_loop = min(theirs[index], key=lambda corner: (placed(corner[0]) - point).length)
            off = (placed(their_point) - point).length
            farthest = max(farthest, off)
            layer.data[loop].uv = uvs[their_loop].uv
    if len(twins) != len(theirs) or farthest > TWIN:
        raise RuntimeError("the textured body isn't the rigged one: %d of %d triangles have a twin, the farthest "
                           "corner %.6f m off (at most %g)" % (len(twins), len(theirs), farthest, TWIN))
    return farthest


def weld(obj):
    """Welds the corners the rig's export split, by position; the UVs stay on the corners."""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    before = len(mesh.verts)
    bmesh.ops.remove_doubles(mesh, verts=mesh.verts, dist=WELD)
    after = len(mesh.verts)
    mesh.to_mesh(obj.data)
    mesh.free()
    return before, after


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    rigged_path, textured_path, out = args[0], args[1], args[2]
    size = int(args[3]) if len(args) > 3 else 1024
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigged = load(rigged_path)
    rigs = [obj for obj in rigged if obj.type == "ARMATURE"]
    bodies = [obj for obj in rigged if obj.type == "MESH"
              and any(modifier.type == "ARMATURE" for modifier in obj.modifiers)]
    if len(rigs) != 1 or len(bodies) != 1:
        raise RuntimeError("%s: %d rigs and %d skinned meshes, not one each" % (rigged_path, len(rigs), len(bodies)))
    rig, body = rigs[0], bodies[0]
    for obj in rigged:
        if obj not in (rig, body):
            bpy.data.objects.remove(obj, do_unlink=True)
    # The clips come from the clip library: the body carries none.
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    rig.animation_data_clear()
    textured = [obj for obj in load(textured_path) if obj.type == "MESH"]
    if len(textured) != 1:
        raise RuntimeError("%s: %d meshes, not one" % (textured_path, len(textured)))
    farthest = transfer(body, textured[0])
    print("BODY UVs moved over from %s, the farthest corner %.7f m off" % (os.path.basename(textured_path), farthest))
    material = textured[0].data.materials[0]
    colour = source_material.strip(material, size)
    if colour is None:
        raise RuntimeError("%s has no base colour texture" % textured_path)
    body.data.materials.clear()
    body.data.materials.append(material)
    bpy.data.objects.remove(textured[0], do_unlink=True)
    before, after = weld(body)
    print("BODY welded %d corners into %d vertices" % (before, after))
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    if body.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bpy.ops.object.shade_smooth()
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_animations=False,
        export_skins=True,
        export_yup=True,
        export_image_format="JPEG",
        export_jpeg_quality=QUALITY,
    )
    differences = skeleton.differences(skeleton.read(SKELETON), skeleton.read(out))
    for line in differences:
        print("SKELETON %s" % line)
    if differences:
        raise RuntimeError("the body's skeleton isn't the clip library's (SKELETON lines)")
    print("BODY %s: %d triangles, colour %dx%d, the clip library's skeleton"
          % (out, len(body.data.polygons), *colour.image.size))


main()
