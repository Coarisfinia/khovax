"""Whether each eye stays under its brow (the owner, on #1249): seen from the front, from the
eye's side and straight into the eye, no part of an eye may show above the brow (or any other
surface) that crosses it. A brow may overlap the eye; the eye's top shining through above it
fails.

An eye is what `eyes.eye` builds: its pieces are islands of the mesh in other materials than the
body's, around the eye's attachment point (`eye.*`, at the iris's centre, looking out along the
bone, attachments.add). The iris is the island nearest that point; its reach gives the eye's
size roughly (about IRIS_SHARE of its radius), and every island in other materials than the body's whose
centre lies within REACH of the point is the eye's: the eyeball, iris, pupil, glint and rim, never
a brow crystal or a nose, whose centres lie further out. The eye's radius is then how far its
pieces reach from the point.

Each view casts a grid of rays at the eye, SPAN of its size to either side, STEP apart, and labels
each ray by what it hits first: the eye, something else (a cover) or nothing. Going up each
column of the grid, an eye seen above a cover that is itself above the eye is the eye showing
through above its brow; the check measures how much of the eye shows so, as a share of the eye's
disc, so a speck of its rim poking through the brow's edge (a slight overlap) passes and an arc of
it above the brow doesn't."""

import math

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import imported

EYE = "eye."
# The iris's reach against the eye's radius (eyes.eye: 0.7 across).
IRIS_SHARE = 0.7
# How far from its attachment point (in the iris's guess of the eye's radius) an eye's pieces'
# centres lie: its eyeball's, with room to spare, short of a brow crystal or a nose.
REACH = 2.0
# The grid each view casts, in the eye's radius: SPAN to either side of the eye, rays STEP apart.
SPAN = 1.5
STEP = 1.0 / 16.0
# How many rays a cover must span up a column to count as one crossing the eye (a brow): a speck
# of the skin poking through the eye's rim is no brow.
MIN_COVER = 3
# How far from the eye's attachment point (in its radius) a cover may lie and still be on the eye:
# its brow, never its snout.
COVER_REACH = 1.2
# How far back from the eye each ray starts (metres): outside the head.
BACK = 1.0


def _islands(mesh):
    """Each face's island: faces sharing a vertex are on one island."""
    parent = list(range(len(mesh.vertices)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for polygon in mesh.polygons:
        first = find(polygon.vertices[0])
        for vertex in polygon.vertices[1:]:
            parent[find(vertex)] = first
    return [find(polygon.vertices[0]) for polygon in mesh.polygons]


class Model:
    """The skinned meshes as one set of faces, with each face's material and island, posed at the
    scene's current frame by `points`."""

    def __init__(self, meshes):
        self.meshes = meshes
        self.faces, self.material, self.island = [], [], []
        offset = 0
        for obj in meshes:
            islands = _islands(obj.data)
            for polygon, island in zip(obj.data.polygons, islands):
                self.faces.append([offset + vertex for vertex in polygon.vertices])
                self.material.append(obj.material_slots[polygon.material_index].name
                                     if obj.material_slots else "")
                self.island.append((obj.name, island))
            offset += len(obj.data.vertices)
        counts = {}
        for name in self.material:
            counts[name] = counts.get(name, 0) + 1
        # The body's material: the one most faces have.
        self.body = max(sorted(counts), key=lambda name: counts[name])

    def points(self):
        depsgraph = bpy.context.evaluated_depsgraph_get()
        found = []
        for obj in self.meshes:
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            found += [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            evaluated.to_mesh_clear()
        return found


def eye_bones(rig):
    return sorted(bone.name for bone in rig.data.bones if bone.name.startswith(EYE))


def _spot(rig, bone):
    pose = rig.pose.bones[bone]
    head = rig.matrix_world @ pose.head
    return head, (rig.matrix_world @ pose.tail - head).normalized()


def eye_faces(model, points, spot):
    """The faces of the eye at `spot`, and its radius, from the rest pose's `points`."""
    others = [index for index, name in enumerate(model.material) if name != model.body]
    tree = BVHTree.FromPolygons(points, [model.faces[index] for index in others])
    _location, _normal, nearest, _distance = tree.find_nearest(spot)
    if nearest is None:
        return set(), 0.0
    iris = model.island[others[nearest]]
    reach = max((points[vertex] - spot).length for index in others if model.island[index] == iris
                for vertex in model.faces[index])
    guess = reach / IRIS_SHARE
    by_island = {}
    for index in others:
        by_island.setdefault(model.island[index], []).append(index)
    faces = set()
    for members in by_island.values():
        corners = {vertex for index in members for vertex in model.faces[index]}
        centre = sum((points[vertex] for vertex in corners), Vector()) / len(corners)
        if (centre - spot).length <= REACH * guess:
            faces.update(members)
    # The eye's own radius: how far its pieces reach, its rim's outer edge.
    radius = max((points[vertex] - spot).length for index in faces for vertex in model.faces[index])
    return faces, radius


def views(spot, look):
    """(name, direction a ray travels) for each view of an eye at `spot` looking along `look`: from
    the model's front (Blender's -Y after import), from the eye's own side and straight into it."""
    side = Vector((1.0 if spot.x >= 0.0 else -1.0, 0.0, 0.0))
    return [("front", Vector((0.0, 1.0, 0.0))), ("side", -side), ("into", -look)]


def above(tree, eye, spot, radius, direction):
    """How much of the eye shows above a cover that crosses it, seen along `direction`: as a share
    of the eye's disc (pi times its radius squared)."""
    up = Vector((0.0, 0.0, 1.0))
    up = (up - direction * up.dot(direction)).normalized()
    right = direction.cross(up)
    count = int(round(SPAN / STEP))
    # Bottom to top in each column: 0 nothing, 1 the eye, 2 a cover on the eye, 3 anything else.
    grid = []
    for column in range(-count, count + 1):
        labels = []
        for row in range(-count, count + 1):
            point = spot + (right * column + up * row) * STEP * radius
            location, _normal, face, _distance = tree.ray_cast(point - direction * BACK, direction)
            if face is None:
                labels.append(0)
            elif face in eye:
                labels.append(1)
            else:
                # Only a cover lying on the eye can be its brow: a snout or a paw passing in front of
                # it hides it, and an eye seen past one isn't shining through anything.
                labels.append(2 if (location - spot).length <= COVER_REACH * radius else 3)
        grid.append(labels)
    shown = 0
    for column, labels in enumerate(grid):
        seen, covered, cover = False, False, 0
        for row, label in enumerate(labels):
            # A cover counts where its rays' neighbours to either side are cover too: a sliver of
            # skin poking through the eye is no brow.
            solid = label == 2 and all(grid[side][row] == 2 for side in (column - 1, column + 1)
                                       if 0 <= side < len(grid))
            if label == 1:
                if cover >= MIN_COVER:
                    covered = True
                cover = 0
                if covered:
                    shown += 1
                seen = True
            elif solid and seen:
                cover += 1
            else:
                # A speck, a gap or the eye's own edge breaks a cover's run.
                cover = 0
                if label == 3:
                    # Something in front of the eye cuts the column: start over above it.
                    seen, covered = False, False
    # Each ray stands for a STEP-wide square of the eye's radius; the eye's disc is pi of them.
    return shown * STEP * STEP / math.pi


def report(rig, meshes, tolerance, every=2):
    """At rest, and in every clip on every `every`th frame and its last: how much of any eye shows
    above a cover crossing it, the worst view and frame. Each fails past `tolerance` (a share of
    the eye's disc).
    Returns (lines, passed); a model without eyes has nothing to check and passes."""
    eyes = eye_bones(rig)
    if not eyes:
        return ["no eye points: nothing to check"], True
    model = Model(meshes)
    scene = bpy.context.scene
    if rig.animation_data is not None:
        rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    scene.frame_set(scene.frame_current)
    rest = model.points()
    found = {}
    for bone in eyes:
        spot, _look = _spot(rig, bone)
        found[bone] = eye_faces(model, rest, spot)
        if not found[bone][0]:
            return ["FAIL %s: no eye pieces around it" % bone], False

    def worst_at(frame):
        """The most of any eye shown above its brow at the scene's current pose, and where."""
        tree = BVHTree.FromPolygons(model.points(), model.faces)
        worst, at = 0.0, None
        for bone in eyes:
            spot, look = _spot(rig, bone)
            faces, radius = found[bone]
            for view, direction in views(spot, look):
                shown = above(tree, faces, spot, radius, direction)
                if at is None or shown > worst:
                    worst, at = shown, (frame, bone, view)
        return worst, at

    # The rest pose first, so a model without clips is checked too, then every clip.
    poses = [("rest", [worst_at(scene.frame_current)])]
    actions = sorted(bpy.data.actions, key=lambda a: a.name) if rig.animation_data is not None else []
    for action in actions:
        start, end = imported.play(rig, action)
        found_in = []
        for frame in sorted(set(range(start, end + 1, every)) | {end}):
            scene.frame_set(frame)
            found_in.append(worst_at(frame))
        poses.append((action.name, found_in))
    lines, passed = [], True
    for name, measured in poses:
        worst, at = max(measured, key=lambda pair: pair[0])
        fails = worst > tolerance + 1e-9
        passed = passed and not fails
        lines.append("%s %s: %.2f %% of the eye shows above its brow (frame %d, %s, %s view)"
                     % ("FAIL" if fails else "ok", name, worst * 100, *at))
    return lines, passed

