"""The hex footprint (#1520): how far a monster reaches across its hex, seen from above, for
check_footprint.py. The game stands a wild monster at its tile's centre at scale 1 on pointy-top
hexes `SIZE` from centre to corner (HexLayout.SIZE), turned to face a neighbour, so across an
edge. The model faces -Y, so the hex's six edges face -Y, +Y and the four directions 30 degrees
either side of the X axis. A pose's **reach** is the largest projection of any vertex of the
deformed meshes onto those six edge normals, over the hex's inradius: 1.00 touches an edge, below
it stays inside.

Standing in its rest pose, a regular monster keeps 5 % padding inside its hex and a boss, enraged
or stronger one may reach 5 % past it (the owner, on #1514); during its clips each may reach 5 %
further (the owner, on #1533). `REGULAR` and `LARGE` hold the (rest, clips) limits."""

import math

import bpy
import numpy

from . import imported

# The game's hex, centre to corner, in metres (HexLayout.SIZE).
SIZE = 1.0
INRADIUS = SIZE * math.sqrt(3.0) / 2.0
# The six edge normals on the ground plane, the first straight ahead (-Y).
NORMALS = numpy.array([(math.cos(math.radians(a)), math.sin(math.radians(a))) for a in range(270, 630, 60)])
REGULAR = (0.95, 1.05)
LARGE = (1.05, 1.10)


def meshes(rig, objects):
    """Every mesh of the model, skinned or riding on a bone (a horn, a gem), but not the
    importer's bone display shapes."""
    shapes = {bone.custom_shape for bone in rig.pose.bones if bone.custom_shape is not None}
    return [obj for obj in objects if obj.type == "MESH" and obj not in shapes]


def reach(meshes):
    """The reach of the deformed `meshes` at the scene's current frame (see the module's notes)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    far = 0.0
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        coords = numpy.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", coords)
        evaluated.to_mesh_clear()
        if not len(coords):
            continue
        world = numpy.array(evaluated.matrix_world)
        points = coords.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]
        far = max(far, float((points[:, :2] @ NORMALS.T).max()))
    return far / INRADIUS


def report(rig, meshes, limits):
    """The reach in the rig's rest pose, then for every clip, every frame: the largest reach and
    the frame it's on. The rest pose fails past the first of `limits` (rest, clips), a clip past
    the second. Returns (lines, passed); a rig without a mesh fails, rather than passing unseen."""
    if not meshes:
        return ["FAIL no mesh to measure"], False
    rest_limit, clip_limit = limits
    scene = bpy.context.scene
    rig.data.pose_position = "REST"
    scene.frame_set(scene.frame_current)
    far = reach(meshes)
    rig.data.pose_position = "POSE"
    passed = far <= rest_limit
    lines = ["%s rest: reach %.3f of the hex (limit %.2f)" % ("ok" if passed else "FAIL", far, rest_limit)]
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        start, end = imported.play(rig, action)
        far, at = 0.0, start
        for number in range(start, end + 1):
            scene.frame_set(number)
            value = reach(meshes)
            if value > far:
                far, at = value, number
        fails = far > clip_limit
        passed = passed and not fails
        lines.append("%s %s: reach %.3f of the hex (frame %d, limit %.2f)" % (
            "FAIL" if fails else "ok", action.name, far, at, clip_limit))
    return lines, passed
