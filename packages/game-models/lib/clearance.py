"""Clearance (#1227): how close each wisp (lib/wisps.py) comes to the rest of the mesh, for
check_clearance.py. A wisp is the part of the skinned meshes its `wisp.*` bone moves most; the body
is every face of them no wisp's bone moves most, all meshes together. A wisp **crosses** the body
when their faces intersect, or when it sits wholly inside the body, where no faces cross: every
ray from its centre along the six axes leaves the body through the back of a face (a nearest
face's normal alone misleads, since the body's joined parts leave faces inside it). Otherwise its
gap is the smallest distance between the two: from its vertices to the body's faces, and from the
body's vertices near it to its faces."""

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import imported
from .wisps import PREFIX

AXES = [Vector(axis) * sign for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1)) for sign in (1, -1)]
# How far past a wisp's own radius (metres) body faces count as near it, for the body's vertices.
REACH = 0.05


class Model:
    """The skinned meshes' vertices, in one list, and their faces split into each wisp's and the
    body's, with the bone that moves each vertex most (to name where a wisp comes close)."""

    def __init__(self, meshes, wisps):
        self.meshes = meshes
        self.owner = []
        self.wisp_vertices = {name: [] for name in wisps}
        self.wisp_faces = {name: [] for name in wisps}
        self.body_faces = []
        # Faces with corners on a wisp and on the body: a wisp joined to the body isn't free.
        self.joined = set()
        for obj in meshes:
            offset = len(self.owner)
            names = {group.index: group.name for group in obj.vertex_groups}
            for vertex in obj.data.vertices:
                top = max(vertex.groups, key=lambda g: g.weight) if vertex.groups else None
                name = None if top is None else names.get(top.group)
                if name in self.wisp_vertices:
                    self.wisp_vertices[name].append(len(self.owner))
                self.owner.append(name)
            for polygon in obj.data.polygons:
                corners = [offset + index for index in polygon.vertices]
                on = {self.owner[index] for index in corners} & set(wisps)
                if not on:
                    self.body_faces.append(corners)
                elif len(on) == 1 and all(self.owner[index] in on for index in corners):
                    self.wisp_faces[next(iter(on))].append(corners)
                else:
                    self.joined |= on

    def points(self):
        """Every vertex where the scene's current frame poses it, in world space."""
        depsgraph = bpy.context.evaluated_depsgraph_get()
        points = []
        for obj in self.meshes:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            world = evaluated.matrix_world
            points.extend(world @ vertex.co for vertex in mesh.vertices)
            evaluated.to_mesh_clear()
        return points


def inside(body, point):
    """Whether `point` is inside the body: the first face every axis ray hits faces away from it."""
    for axis in AXES:
        location, normal, _face, _distance = body.ray_cast(point, axis)
        if location is None or normal.dot(axis) <= 0.0:
            return False
    return True


def wisp_bones(rig):
    return sorted(bone.name for bone in rig.pose.bones if bone.name.startswith(PREFIX))


def measure(model):
    """Per wisp, at the scene's current frame: (gap in metres, crosses, the body bone nearest)."""
    points = model.points()
    body = BVHTree.FromPolygons(points, model.body_faces)
    found = {}
    for name, indices in model.wisp_vertices.items():
        wisp = BVHTree.FromPolygons(points, model.wisp_faces[name])
        centre = sum((points[index] for index in indices), Vector()) / len(indices)
        radius = max((points[index] - centre).length for index in indices)
        crosses = bool(body.overlap(wisp)) or inside(body, centre)
        gap, near = float("inf"), None
        for index in indices:
            location, _normal, face, distance = body.find_nearest(points[index])
            if face is not None and distance < gap:
                corners = model.body_faces[face]
                closest = min(corners, key=lambda corner: (points[corner] - location).length)
                gap, near = distance, model.owner[closest]
        # The other way round: a body vertex (an ear's tip) can come closer to a wisp's face than
        # any of the wisp's vertices comes to the body.
        for _location, _normal, face, _distance in body.find_nearest_range(centre, radius + REACH):
            for corner in model.body_faces[face]:
                _at, _normal, wisp_face, distance = wisp.find_nearest(points[corner])
                if wisp_face is not None and distance < gap:
                    gap, near = distance, model.owner[corner]
        found[name] = (gap, crosses, near)
    return found


def report(rig, meshes, tolerance):
    """For every clip, every frame: the smallest gap between any wisp and the body, the frame and
    the wisp and body bone it's between, and the frames a wisp crosses the body (the first one's
    wisp and body bone). A clip fails when one does, or when the gap falls below `tolerance`.
    Returns (lines, passed); a model without wisps has nothing to check and passes."""
    wisps = wisp_bones(rig)
    if not wisps:
        return ["no wisp bones: nothing to check"], True
    model = Model(meshes, wisps)
    # A wisp bone that moves no part of the mesh can't be measured, and one joined to the body
    # isn't free: both fail, rather than passing unseen.
    unweighted = [name for name in wisps if not model.wisp_vertices[name]]
    if unweighted or model.joined:
        problems = ["%s moves no part of the mesh" % name for name in unweighted]
        problems += ["%s shares a face with the body" % name for name in sorted(model.joined)]
        return ["FAIL wisps: " + "; ".join(problems)], False
    scene = bpy.context.scene
    lines, passed = [], True
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        start, end = imported.play(rig, action)
        low, at, crossing, where = float("inf"), None, [], None
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            found = measure(model)
            crossers = sorted((name, near) for name, (_gap, crosses, near) in found.items() if crosses)
            if crossers:
                crossing.append(frame)
                where = where or crossers[0]
            for name, (gap, crosses, near) in found.items():
                if not crosses and gap < low:
                    low, at = gap, (frame, name, near)
        fails = bool(crossing) or low < tolerance
        passed = passed and not fails
        if at is None:
            text = "no wisp clear of the body on any frame"
        else:
            text = "min %.1f mm (frame %d, %s by %s)" % (low * 1000, *at)
        if crossing:
            text += "; a wisp crosses the body on %d of %d frames (%s; first %s by %s)" % (
                len(crossing), end - start + 1, " ".join(str(frame) for frame in crossing), *where)
        lines.append("%s %s: %s" % ("FAIL" if fails else "ok", action.name, text))
    return lines, passed
