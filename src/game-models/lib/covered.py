"""Whether the body covers any part of our eyes (the owner, on #1747 and #1758): no surface of
the body may poke through an eye or sit in front of it, anywhere within its rim, nor over its lid
when shut.

An eye is what `eyes.eye` builds, found as lib/brows.py finds it: the islands in other materials
than the body's around its attachment point (`eye.*`), without the lid's material (the lid and,
on a generated model, the brow). Its pieces are told apart by shape: the **rim** is the ring (the
one piece with a hole), the **eyeball** the largest of the rest, and the iris and pupil what
remains, in front of the eyeball. The eye looks from the eyeball's centre through them, and its
**face** is the rim's outline seen along that way: what must show. The eye's **own pieces**,
which may lie in front of its face, are those islands, the lid's (the faces weighted to a `lid.*`
bone) and any closed piece in the body's material whose centre lies near the eye (a hand-built
eye's brow); every other surface is the body, a generated skin's loose pieces included (the
Wobulumu's, #1758). Islands are told apart with the vertices welded by position, since a glTF's
skin comes apart along its UV seams.

The eye is looked at **straight on**, along the way it looks: from there, nothing but its own
pieces may lie in front of its face, whatever the angle the game shows it from (from the side,
the head's own curve hides an eye set into it, as it should). A grid of rays, STEP of its radius
apart, is cast at it; a ray whose hit on the eye lies within its face counts, and it is
**covered** when the first thing it hits is the body. The check measures the covered rays as a
share of those, at rest and in every clip, so a crescent of skin across the eye fails."""

import math

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import brows, imported

LID = "lid."
# The grid cast at the eye, in its radius: across its whole disc, rays STEP apart.
SPAN = 1.0
STEP = 1.0 / 24.0
# How far back from the eye each ray starts (metres): outside the head.
BACK = 1.0
# How many directions round the eye its rim's outline is measured in (`Eye.face`).
SECTORS = 32
# Vertices closer than this (metres) are one when telling the pieces apart (welded).
WELD = 1e-5


def lid_faces(model, meshes):
    """The faces most of whose corners are weighted mostly to a lid's bone."""
    faces, offset = set(), 0
    for obj in meshes:
        lids = {group.index for group in obj.vertex_groups if group.name.startswith(LID)}
        on_lid = [bool(vertex.groups) and max(vertex.groups, key=lambda g: g.weight).group in lids
                  for vertex in obj.data.vertices]
        for polygon in obj.data.polygons:
            if 2 * sum(on_lid[vertex] for vertex in polygon.vertices) > len(polygon.vertices):
                faces.add(offset + polygon.index)
        offset += len(obj.data.polygons)
    return faces


def welded(points):
    """Each vertex's first one at its position: a glTF's skin comes apart along its UV seams, its
    vertices doubled there."""
    first = {}
    return [first.setdefault(tuple(round(value / WELD) for value in point), index)
            for index, point in enumerate(points)]


def islands(model, same):
    """Each face's island, its vertices welded (`same`, from `welded`)."""
    parent = list(range(len(same)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for face in model.faces:
        for vertex in face[1:]:
            parent[find(same[vertex])] = find(same[face[0]])
    return [find(same[face[0]]) for face in model.faces]


def _corners(model, points, faces):
    return [points[vertex] for vertex in {vertex for index in faces for vertex in model.faces[index]}]


def _centre(corners):
    return sum(corners, Vector()) / len(corners)


def _euler(model, same, faces):
    """Vertices minus edges plus faces of `faces`, its vertices welded (`same`)."""
    vertices, edges = set(), set()
    for index in faces:
        corners = [same[vertex] for vertex in model.faces[index]]
        vertices.update(corners)
        edges.update(tuple(sorted((corners[i - 1], corners[i]))) for i in range(len(corners)))
    return len(vertices) - len(edges) + len(faces)


class Eye:
    """One eye's faces, as the module says: `rim`, `eyeball` and `front` (iris and pupil), the eye
    `itself` (all three), its `own` pieces and its `radius` (from lib/brows.py)."""

    def __init__(self, model, points, spot, lids, same, island):
        eye, self.radius = brows.eye_faces(model, points, spot)
        lid_materials = {model.material[index] for index in lids}
        by_piece = {}
        for index in eye:
            if model.material[index] not in lid_materials:
                by_piece.setdefault(island[index], set()).add(index)
        self.itself = set().union(*by_piece.values()) if by_piece else set()
        self.rim, self.eyeball, self.front = set(), set(), set()
        if len(by_piece) >= 3:
            def reach(faces):
                corners = _corners(model, points, faces)
                centre = _centre(corners)
                return max((corner - centre).length for corner in corners)

            pieces = list(by_piece.values())
            # The rim is the one ring (eyes.eye's torus, the only piece with a hole: its vertices,
            # edges and faces add up to 0, a ball's to 2), the eyeball the largest of the balls.
            rims = [piece for piece in pieces if _euler(model, same, piece) == 0]
            if rims:
                self.rim = rims[0]
                pieces = [piece for piece in pieces if piece is not self.rim]
                self.eyeball = max(pieces, key=reach)
                self.front = set().union(*(piece for piece in pieces if piece is not self.eyeball))
        self.own = set(eye) | lids
        by_island = {}
        for index, material in enumerate(model.material):
            if material == model.body:
                by_island.setdefault(island[index], []).append(index)
        for members in by_island.values():
            # A hand-built eye's brow: a closed piece of its own over it. A generated skin's loose
            # pieces are open surfaces, and one over the eye covers it (#1758), as does a closed
            # piece lower down.
            centre = _centre(_corners(model, points, members))
            if ((centre - spot).length <= brows.REACH * self.radius and centre.z > spot.z
                    and _euler(model, same, members) == 2):
                self.own.update(members)

    def face(self, model, points):
        """The eye's face at `points`' pose: (its centre, the way it looks, a function telling
        whether a point lies within the rim's outline seen along that way), or None when the eye
        has no outline to look at (squashed flat)."""
        rim = _corners(model, points, self.rim)
        centre = _centre(rim)
        look = (_centre(_corners(model, points, self.front))
                - _centre(_corners(model, points, self.eyeball)))
        if look.length < 1e-9:
            return None
        look.normalize()
        side = look.orthogonal().normalized()
        up = look.cross(side)
        # The rim's outline round the way it looks, as its reach in each of SECTORS directions
        # (the furthest of its corners there), whatever its shape and tilt (eyes.eye's `almond`
        # and `tilt`); a sector no corner falls in takes the nearer of the reaches on either side.
        reach = [0.0] * SECTORS
        for corner in rim:
            offset = corner - centre
            across = Vector((offset.dot(side), offset.dot(up)))
            sector = int((math.atan2(across.y, across.x) / math.tau) % 1.0 * SECTORS) % SECTORS
            reach[sector] = max(reach[sector], across.length)
        if max(reach) <= 0.0:
            return None
        filled = list(reach)
        for sector in range(SECTORS):
            if reach[sector] <= 0.0:
                sides = [next(reach[(sector + way * step) % SECTORS] for step in range(1, SECTORS)
                              if reach[(sector + way * step) % SECTORS] > 0.0) for way in (-1, 1)]
                filled[sector] = min(sides)
        reach = filled

        def within(point):
            offset = point - centre
            across = Vector((offset.dot(side), offset.dot(up)))
            sector = int((math.atan2(across.y, across.x) / math.tau) % 1.0 * SECTORS) % SECTORS
            return across.length <= reach[sector]

        return centre, look, within


def covered(tree, eye_tree, own, centre, radius, within, direction):
    """Of the rays along `direction` whose hit on the eye (`eye_tree`) lies within its face, the
    share whose first hit in `tree` is the body, and the lowest and highest of those across the
    eye (in its radius, up it), or None when nothing covers it."""
    up = Vector((0.0, 0.0, 1.0))
    if abs(direction.dot(up)) > 0.99:
        up = Vector((0.0, 1.0, 0.0))
    up = (up - direction * up.dot(direction)).normalized()
    right = direction.cross(up)
    count = int(round(SPAN / STEP))
    seen, hidden, rows = 0, 0, []
    for column in range(-count, count + 1):
        for row in range(-count, count + 1):
            point = centre + (right * column + up * row) * STEP * radius - direction * BACK
            target, _normal, _face, distance = eye_tree.ray_cast(point, direction)
            if target is None or not within(target):
                continue
            seen += 1
            _location, _normal, face, first = tree.ray_cast(point, direction)
            if face is not None and face not in own and first < distance:
                hidden += 1
                rows.append(row * STEP)
    if not seen:
        return 0.0, None
    return hidden / seen, (min(rows), max(rows)) if rows else None


def report(rig, meshes, tolerance, every=2):
    """At rest, and in every clip on every `every`th frame and its last: how much of any eye's face
    the body covers, the eye and frame. Each fails past `tolerance` (a share of the face
    seen). Returns (lines, passed); a model without eyes, or with its eyes painted on its one
    material, has nothing to check and passes."""
    bones = brows.eye_bones(rig)
    if not bones:
        return ["no eye points: nothing to check"], True
    model = brows.Model(meshes)
    scene = bpy.context.scene
    if rig.animation_data is not None:
        rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    scene.frame_set(scene.frame_current)
    if len(set(model.material)) == 1:
        # Its eyes are painted on its skin (a generated model's one textured material, #1476).
        return ["eyes painted on the skin, no eye pieces: nothing to check"], True
    rest = model.points()
    lids = lid_faces(model, meshes)
    same = welded(rest)
    island = islands(model, same)
    eyes = {}
    for bone in bones:
        spot, _look = brows._spot(rig, bone)
        eyes[bone] = Eye(model, rest, spot, lids, same, island)
        if not eyes[bone].rim:
            return ["FAIL %s: no rim, eyeball and iris around it" % bone], False

    def worst_at(frame):
        """The most of any eye the body covers at the scene's current pose, and where."""
        points = model.points()
        tree = BVHTree.FromPolygons(points, model.faces)
        worst, at = 0.0, (frame, bones[0], None)
        for bone, eye in eyes.items():
            face = eye.face(model, points)
            if face is None:
                return 1.0, (frame, bone, None)
            centre, look, within = face
            eye_tree = BVHTree.FromPolygons(points, [model.faces[index] for index in sorted(eye.itself)])
            share, rows = covered(tree, eye_tree, eye.own, centre, eye.radius, within, -look)
            if share > worst:
                worst, at = share, (frame, bone, rows)
        return worst, at

    # The rest pose first, so a model without clips is checked too, then every clip.
    poses = [("rest", [worst_at(scene.frame_current)])]
    actions = sorted(bpy.data.actions, key=lambda a: a.name) if rig.animation_data is not None else []
    for action in actions:
        # Each clip from the rest pose: a bone it doesn't key keeps none of the last clip's pose.
        for bone in rig.pose.bones:
            bone.matrix_basis.identity()
        start, end = imported.play(rig, action)
        found_in = []
        for frame in sorted(set(range(start, end + 1, every)) | {end}):
            scene.frame_set(frame)
            found_in.append(worst_at(frame))
        poses.append((action.name, found_in))
    lines, passed = [], True
    for name, measured in poses:
        worst, (frame, bone, rows) = max(measured, key=lambda pair: pair[0])
        fails = worst > tolerance + 1e-9
        passed = passed and not fails
        where = "" if rows is None else ", from %+.2f to %+.2f of its radius up the eye" % rows
        lines.append("%s %s: the body covers %.2f %% of the eye (frame %d, %s%s)"
                     % ("FAIL" if fails else "ok", name, worst * 100, frame, bone, where))
    return lines, passed
