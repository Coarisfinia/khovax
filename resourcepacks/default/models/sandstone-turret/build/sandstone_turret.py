"""The sandstone turret (#1836, from #1824): an octagonal tower of pale sandstone blocks with a
pointed roof of red clay tiles and one arrow slit, the tower at a hex corner where the fliers'
realm's (#1834) walls meet (the mossy sandstone wall, #1832). Its shape and its paint are the
owner's generated model (`source.glb` beside this script, from the download by import_source.py:
see the asset's SOURCE.md); the paint is the download's own, which held up on every side, its
UVs carried onto the cut pieces by lib/source_uv.py. A
static model: no rig and no clips.

    uv run --locked src/game-models/blender.py --background --factory-startup \
        --python resourcepacks/default/models/sandstone-turret/build/sandstone_turret.py -- resourcepacks/default/models/sandstone-turret/sandstone_turret.glb

It's a tower on the world's scale (lib/world_scale.py, #1837): it stands at a hex corner, its
origin at the corner, and the wall pieces' ends meet inside it. The prompt asked for a tower as
wide as two walls are thick (`BODY_WIDTH`), and a tower stands above the walls, while the download
is a squat tower, not even twice as tall as it is wide. So the script keeps the download whole,
scaled alike in every direction, cuts it at a mortar joint below the slit and stacks copies of two
of its courses there (`COURSES`), each turned an eighth further so the same stones don't line up,
until its eaves stand a course above a wall. Its foot is cut flat above the download's strip of
grass: the ground is ours. Its flats face the game's ±X, ±Z and the diagonals between, so a wall
along an edge in the game's Z meets a flat.

Blender is Z-up and its slit looks along -Y (the game's +Z); the origin is at its foot."""

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

from lib import fixed_order, scene, source_uv, world_scale  # noqa: E402

SOURCE = os.path.join(HERE, "source.glb")
FPS = 30
# Its kind on the world's scale (lib/world_scale.py): a tower at a hex corner, above the walls.
WORLD_SCALE = "tower"
# Edges sharper than this stay sharp in the shading: the blocks' corners, the roof's tiles.
SHARP = math.radians(40.0)
# Across its flats, in metres: twice the mossy wall's depth (the prompt's "as wide as two wall
# thicknesses"), so a wall's end hides inside it.
BODY_WIDTH = 0.76

# In the download's own units (heights along its Z):
# the top of its strip of grass, where its foot is cut;
GRASS_TOP = -0.395
# the mortar joints bounding the two courses stacked in (`COURSES`), below the slit; the download
# is cut at the upper one and the copies go in there;
COURSES = (-0.37, -0.195)
# its eaves, where the roof starts;
EAVES = 0.03
# and the band of the body measured for its width (the courses above the foot, below the slit).
BODY = (-0.37, -0.11)
# How far each piece sinks into the one below, so no gap shows at a joint.
SINK = 0.004
# How far the eaves stand above a wall's top, in courses (half a stacked copy).
CLEAR = 1
# The vertices are rounded to this many decimals (metres) before the export: another machine's
# maths differ in the last bits, which would reorder the sorted export (check_rebuild.py).
DECIMALS = 5


def body_scale(points):
    """The scale that makes the body `BODY_WIDTH` across its flats, which face ±X: the band's
    width along X."""
    band = points[(points[:, 2] > BODY[0]) & (points[:, 2] < BODY[1])]
    return round(BODY_WIDTH / float(band[:, 0].max() - band[:, 0].min()), 4)


def copies(size):
    """How many copies of `COURSES` go in, so the eaves stand `CLEAR` courses above a wall."""
    course = (COURSES[1] - COURSES[0]) / 2.0
    stacked = COURSES[1] - COURSES[0] - SINK
    short = (world_scale.WALL_HEIGHT / size + CLEAR * course) - (EAVES - GRASS_TOP)
    return max(0, math.ceil(short / stacked))


def piece(source_mesh, uvs, low, high):
    """The download between the heights `low` and `high` (None: its end), cut flat, as a bmesh with
    the download's UVs (`uvs`, a lib/source_uv.py `Source`)."""
    work = bmesh.new()
    work.from_mesh(source_mesh)
    fixed_order.weld(work)
    if low is not None:
        fixed_order.cut(work, Vector((0.0, 0.0, low)), Vector((0.0, 0.0, -1.0)))
    if high is not None:
        fixed_order.cut(work, Vector((0.0, 0.0, high)), Vector((0.0, 0.0, 1.0)))
    source_uv.transfer(work, uvs)
    return work


def add(stack, work, rise, turn):
    """Puts `work` into `stack`, turned by `turn` about the axis and raised by `rise`."""
    bmesh.ops.rotate(work, verts=work.verts, cent=Vector(), matrix=Matrix.Rotation(turn, 3, "Z"))
    bmesh.ops.translate(work, verts=work.verts, vec=Vector((0.0, 0.0, rise)))
    mesh = bpy.data.meshes.new("piece")
    work.to_mesh(mesh)
    work.free()
    stack.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


def build(source):
    """The turret: the download's foot, the stacked copies and the download's top, sized, as one
    mesh object."""
    points = numpy.array([vertex.co[:] for vertex in source.data.vertices])
    size = body_scale(points)
    count = copies(size)
    uvs = source_uv.Source(source.data)
    stack = bmesh.new()
    # The foot, from the grass up to the cut, standing on z 0.
    add(stack, piece(source.data, uvs, GRASS_TOP, COURSES[1]), -GRASS_TOP, 0.0)
    rise = COURSES[1] - GRASS_TOP - SINK
    for index in range(count):
        # Each copy starts at the lower joint, sitting on the cut below.
        add(stack, piece(source.data, uvs, COURSES[0], COURSES[1]), rise - COURSES[0], math.radians(45.0) * (index + 1))
        rise += COURSES[1] - COURSES[0] - SINK
    # The top, from the cut to the roof's tip, with the slit, as the download has it.
    add(stack, piece(source.data, uvs, COURSES[1], None), rise - COURSES[1], 0.0)
    bmesh.ops.scale(stack, verts=stack.verts, vec=Vector((size, size, size)))
    # Onto a fine grid, where another machine's float maths lands alike; the export puts the faces
    # in a fixed order (lib/scene.py), and fixed_order.canonical would drop the UVs.
    for vert in stack.verts:
        vert.co = Vector([round(value, DECIMALS) for value in vert.co])
    mesh = bpy.data.meshes.new("SandstoneTurret")
    stack.to_mesh(mesh)
    stack.free()
    turret = bpy.data.objects.new("SandstoneTurret", mesh)
    bpy.context.scene.collection.objects.link(turret)
    turret.data.materials.append(source.data.materials[0])
    bpy.data.objects.remove(source)
    eaves = (rise + EAVES - COURSES[1]) * size
    return turret, size, count, eaves


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
    turret, size, count, eaves = build(source)
    scene.select_only(turret)
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)
    if eaves <= world_scale.WALL_HEIGHT:
        raise SystemExit("the eaves stand at %.3f m, not above a wall (%.3f m)" % (eaves, world_scale.WALL_HEIGHT))

    points = numpy.array([vertex.co[:] for vertex in turret.data.vertices])
    _length, height = world_scale.bounds(points)
    print("BUDGET triangles", scene.triangles(turret), "materials", len(turret.data.materials),
          "scale %.4f" % size, "copies", count, "height %.3f" % height, "eaves %.3f" % eaves,
          "width %.3f" % (points[:, 0].max() - points[:, 0].min()),
          "depth %.3f" % (points[:, 1].max() - points[:, 1].min()))
    scene.export_glb(out)


main()
