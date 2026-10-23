"""Clearance (#1227): how close each wisp (lib/wisps.py) comes to the rest of the mesh, for
check_clearance.py. A wisp is the part of a skinned mesh its `wisp.*` bone moves most; the body is
every face no wisp's bone moves most. A wisp **crosses** the body when their faces intersect, or
when it sits wholly inside the body, where no faces cross: every ray from its centre along the six
axes leaves the body through the back of a face (a nearest face's normal alone misleads, since
the body's joined parts leave faces inside it). Otherwise its gap is the smallest distance from
its vertices to the body's faces."""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import imported
from .wisps import PREFIX


class Split:
    """One mesh's vertices and faces, split into each wisp's and the body's, with the bone that
    moves each body face's corners most (to name where a wisp comes close)."""

    def __init__(self, obj, wisps):
        self.obj = obj
        names = {group.index: group.name for group in obj.vertex_groups}
        owner = []
        for vertex in obj.data.vertices:
            top = max(vertex.groups, key=lambda g: g.weight) if vertex.groups else None
            owner.append(None if top is None else names.get(top.group))
        self.wisp_vertices = {name: [] for name in wisps}
        for index, name in enumerate(owner):
            if name in self.wisp_vertices:
                self.wisp_vertices[name].append(index)
        self.wisp_faces = {name: [] for name in wisps}
        self.body_faces = []
        self.body_bones = []
        for polygon in obj.data.polygons:
            corners = list(polygon.vertices)
            moved = {owner[index] for index in corners}
            if len(moved) == 1 and next(iter(moved)) in self.wisp_faces:
                self.wisp_faces[next(iter(moved))].append(corners)
            elif not moved & set(wisps):
                self.body_faces.append(corners)
                self.body_bones.append([owner[index] for index in corners])


AXES = [Vector(axis) * sign for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1)) for sign in (1, -1)]


def inside(body, point):
    """Whether `point` is inside the body: the first face every axis ray hits faces away from it."""
    for axis in AXES:
        location, normal, _face, _distance = body.ray_cast(point, axis)
        if location is None or normal.dot(axis) <= 0.0:
            return False
    return True


def wisp_bones(rig):
    return sorted(bone.name for bone in rig.pose.bones if bone.name.startswith(PREFIX))


def measure(splits):
    """Per wisp, at the scene's current frame: (gap in metres, crosses, the body bone nearest)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    found = {}
    for split in splits:
        evaluated = split.obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        world = evaluated.matrix_world
        points = [world @ vertex.co for vertex in mesh.vertices]
        evaluated.to_mesh_clear()
        body = BVHTree.FromPolygons(points, split.body_faces)
        for name, indices in split.wisp_vertices.items():
            if not indices:
                continue
            wisp = BVHTree.FromPolygons(points, split.wisp_faces[name])
            centre = sum((points[index] for index in indices), Vector()) / len(indices)
            crosses = bool(body.overlap(wisp)) or inside(body, centre)
            gap, near = float("inf"), None
            for index in indices:
                location, _normal, face, distance = body.find_nearest(points[index])
                if face is not None and distance < gap:
                    corners = split.body_faces[face]
                    closest = min(range(len(corners)), key=lambda i: (points[corners[i]] - location).length)
                    gap, near = distance, split.body_bones[face][closest]
            # A wisp split over several meshes keeps its smallest gap, and crosses if any part does.
            previous = found.get(name, (float("inf"), False, None))
            nearest = (gap, near) if gap < previous[0] else (previous[0], previous[2])
            found[name] = (nearest[0], crosses or previous[1], nearest[1])
    return found


def report(rig, meshes, tolerance):
    """For every clip, every frame: the smallest gap between any wisp and the body, the frame and
    the wisp and body bone it's between, and the frames a wisp crosses the body (the first one's
    wisp and body bone). A clip
    fails when one does, or when the gap falls below `tolerance`. Returns (lines, passed); a
    model without wisps has nothing to check and passes."""
    wisps = wisp_bones(rig)
    if not wisps:
        return ["no wisp bones: nothing to check"], True
    splits = [Split(obj, wisps) for obj in meshes]
    unweighted = [name for name in wisps if not any(split.wisp_vertices[name] for split in splits)]
    if unweighted:
        # A wisp bone that moves no part of the mesh can't be measured: that fails, rather than
        # passing unseen.
        return ["FAIL: %s move no part of the mesh" % ", ".join(unweighted)], False
    scene = bpy.context.scene
    lines, passed = [], True
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        start, end = imported.play(rig, action)
        low, at, crossing, where = float("inf"), None, [], None
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            found = measure(splits)
            crossers = sorted((name, near) for name, (_gap, crosses, near) in found.items() if crosses)
            if crossers:
                crossing.append(frame)
                where = where or crossers[0]
            for name, (gap, crosses, near) in found.items():
                if not crosses and gap < low:
                    low, at = gap, (frame, name, near)
        fails = bool(crossing) or low < tolerance
        passed = passed and not fails
        text = "min %.1f mm" % (low * 1000)
        if at is not None:
            text += " (frame %d, %s by %s)" % at
        if crossing:
            text += "; a wisp crosses the body on %d of %d frames (%s; first %s by %s)" % (
                len(crossing), end - start + 1, " ".join(str(frame) for frame in crossing), *where)
        lines.append("%s %s: %s" % ("FAIL" if fails else "ok", action.name, text))
    return lines, passed
