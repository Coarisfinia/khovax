"""Connectivity (#1403): whether every part attached to the skin (a crystal, a gem, a horn, a
claw, a tuft) stays on it in every frame of every clip, for check_connectivity.py. Split off
#1303, where the mana wolf's crest crystal lifted off its neck as it bowed.

A **piece** is a connected part of the skinned meshes: faces that share a vertex, all meshes
together. The export splits a flat-shaded face's corners (a crystal's facets) into vertices of
their own, so vertices at the same place (within WELD) are welded first, or every facet would be
a piece. The **body** is the largest piece by area; every other piece is a **part**. Wisps
(lib/wisps.py) are meant to float, so a piece their bones move most is left out.

A part's **gap** to a piece is the smallest distance from the part's vertices to the piece's
faces, and nothing once their faces cross: a crystal's base sunk into the skin touches it however
deep it sinks. Some parts never touch the skin at rest (a band
around a leg, a tuft beside it), so a gap is judged against itself at rest: its **lift** is how
much it grew. What a part sits on is any piece larger than itself that lies near it at rest
(within NEAR of the nearest one): the body, or the larger part it grows from (a fang on the jaw,
an eye in its lid). A part stays on when it keeps its rest gap to one of them, so its lift is the
smallest of its lifts to each; only larger pieces count, so a cluster of parts can't drift off
holding on to one another. A clip fails when a part lifts more than the tolerance in any frame
(#1303: the wolf's crest crystal lifted 16 to 36 mm before its fix).

The gap can't see a part sink into the skin, which is no coming loose to it: Ombulumo's fronds
vanished into its head while it channelled (#1440) and passed. So a part's **sink** into a piece
it sits on is how much more of its vertices lie inside that piece than at rest, as a share of
them (clearance.inside), since some parts start half sunk (a frond's base, a crystal's) and
only sinking further is news. A part sinks only as far as it does into the piece it sinks least
into, as it lifts only when it does off every one (an eye inside its closing lid stays in its
head as at rest), and a clip fails when a part sinks by more than SINK in any frame (#1458). A
part most of whose vertices lie inside at rest can't sink by that much: a share of vertices says
little about one that is mostly hidden anyway, and a vertex or two more inside isn't sinking."""

import itertools

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import clearance, imported
from .wisps import PREFIX

# How close two vertices must lie (metres) to be welded into one: far below any gap the game's
# models have, far above the export's float noise.
WELD = 1e-5
# How far a part may lift off what it sits on (metres) in any frame: the jaw's fangs and the
# ears' tufts shift a few millimetres against the skin as it stretches, a part coming loose more.
TOLERANCE = 0.005
# How much farther than the nearest larger piece (metres) another one may lie at rest and still
# count as what a part sits on: an eye between its lid and the head, a tuft between two ears.
NEAR = 0.01
# How much larger a share of a part's vertices may lie inside what it sits on than at rest: a jaw
# closing tucks into the head, a frond vanishing into it (#1440) sinks more.
SINK = 0.5


class Model:
    """The skinned meshes' vertices in one list, with the bone that moves each most, cut into
    pieces, each with its faces and area, largest first."""

    def __init__(self, meshes):
        self.meshes = meshes
        self.owner = []
        rest = []
        faces = []
        areas = []
        for obj in meshes:
            offset = len(self.owner)
            names = {group.index: group.name for group in obj.vertex_groups}
            world = obj.matrix_world
            for vertex in obj.data.vertices:
                top = max(vertex.groups, key=lambda g: g.weight) if vertex.groups else None
                self.owner.append(None if top is None else names.get(top.group))
                rest.append(world @ vertex.co)
            scale = world.median_scale ** 2
            for polygon in obj.data.polygons:
                faces.append([offset + index for index in polygon.vertices])
                areas.append(polygon.area * scale)
        parent = list(range(len(rest)))

        def find(index):
            while parent[index] != index:
                parent[index] = parent[parent[index]]
                index = parent[index]
            return index

        # Cells WELD wide: two vertices within WELD of each other lie in the same cell or
        # neighbouring ones, wherever a cell's edge falls between them.
        cells = {}
        for index, point in enumerate(rest):
            cell = tuple(int(value // WELD) for value in point)
            for offset in itertools.product((-1, 0, 1), repeat=3):
                for other in cells.get(tuple(c + o for c, o in zip(cell, offset)), ()):
                    if (rest[other] - point).length <= WELD:
                        parent[find(index)] = find(other)
            cells.setdefault(cell, []).append(index)
        for corners in faces:
            first = find(corners[0])
            for corner in corners[1:]:
                parent[find(corner)] = first
        found = {}
        for corners, area in zip(faces, areas):
            piece = found.setdefault(find(corners[0]), {"faces": [], "area": 0.0})
            piece["faces"].append(corners)
            piece["area"] += area
        pieces = []
        for piece in found.values():
            vertices = sorted({corner for corners in piece["faces"] for corner in corners})
            piece["vertices"] = vertices
            piece["bone"] = self._bone(vertices)
            pieces.append(piece)
        # Largest first: what a part sits on is among the pieces before it.
        pieces.sort(key=lambda piece: -piece["area"])
        self.wisps = [piece for piece in pieces if (piece["bone"] or "").startswith(PREFIX)]
        self.pieces = [piece for piece in pieces if piece not in self.wisps]
        self._name()

    def _bone(self, vertices):
        """The bone that moves most of a piece's vertices."""
        counts = {}
        for index in vertices:
            counts[self.owner[index]] = counts.get(self.owner[index], 0) + 1
        return max(counts, key=lambda name: (counts[name], name or ""))

    def _name(self):
        """Names the body, and each part after its bone, numbered where several share one."""
        seen = {}
        if self.pieces:
            self.pieces[0]["name"] = "body"
        for piece in self.pieces[1:]:
            bone = piece["bone"] or "unweighted"
            seen[bone] = seen.get(bone, 0) + 1
            piece["name"] = bone if seen[bone] == 1 else "%s#%d" % (bone, seen[bone])

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

    def anchor(self, points):
        """Each part's `anchors` at the pose `points` holds (the rest pose): {piece's index: the
        part's gap to it}, for every larger piece within NEAR of the nearest one. Returns the parts
        (every piece but the body)."""
        trees = [BVHTree.FromPolygons(points, piece["faces"]) for piece in self.pieces]
        for number, piece in enumerate(self.pieces[1:], 1):
            piece["index"] = number
            gaps = {candidate: gap(trees[candidate], trees[number], points, piece["vertices"])
                    for candidate in range(number)}
            nearest = min(gaps.values())
            piece["anchors"] = {candidate: value for candidate, value in gaps.items() if value <= nearest + NEAR}
            piece["inside"] = {candidate: inside(trees[candidate], points, piece["vertices"])
                               for candidate in piece["anchors"]}
        return self.pieces[1:]


def gap(tree, part, points, vertices):
    """The smallest distance between the part (`vertices`, `part` a tree of its faces) and the
    faces in `tree`: none once their faces cross, as a crystal's base sunk into the skin does, or
    once the part lies wholly inside them, as an ear the skin bulges over does.
    Both ways round: from the part's vertices to the faces, and from the faces' vertices near the
    part to its faces, since a lip's edge can come closer to a fang's side than any of the fang's
    corners comes to the lip. Measured at points, never between two faces' insides, it can read a
    little long (never short), far below the tolerance for the small parts this checks. `overlap`
    tests the faces themselves, not only their boxes."""
    if tree.overlap(part) or clearance.inside(tree, points[vertices[0]]):
        return 0.0
    low = float("inf")
    for index in vertices:
        _location, _normal, face, distance = tree.find_nearest(points[index])
        if face is not None:
            low = min(low, distance)
    centre = sum((points[index] for index in vertices), Vector()) / len(vertices)
    radius = max((points[index] - centre).length for index in vertices)
    for location, _normal, _face, _distance in tree.find_nearest_range(centre, radius + low):
        _at, _normal, face, distance = part.find_nearest(location)
        if face is not None:
            low = min(low, distance)
    return low


def inside(tree, points, vertices):
    """The share of `vertices` that lie inside the faces in `tree`."""
    return sum(1 for index in vertices if clearance.inside(tree, points[index])) / len(vertices)


def sink(model, part, points, trees):
    """How far `part` sinks into what it sits on where `points` poses the meshes: how much larger a
    share of its vertices lies inside than at rest, the least into any of its anchors, and that
    anchor's name."""
    best, name = float("inf"), None
    for anchor, rest in part["inside"].items():
        sunk = inside(tree(model, anchor, points, trees), points, part["vertices"]) - rest
        if sunk < best:
            best, name = sunk, model.pieces[anchor]["name"]
    return best, name


def lift(model, part, points, trees):
    """How far `part` lifts off what it sits on where `points` poses the meshes: the smallest
    growth of its gap to any of its anchors, and that anchor's name. `trees` caches each piece's
    faces for this pose."""
    best, name = float("inf"), None
    for anchor, rest in part["anchors"].items():
        grown = gap(tree(model, anchor, points, trees), tree(model, part["index"], points, trees), points,
                    part["vertices"]) - rest
        if grown < best:
            best, name = grown, model.pieces[anchor]["name"]
    return best, name


def tree(model, index, points, trees):
    """The faces of the piece `index` where `points` poses them, cached in `trees` for the pose."""
    if index not in trees:
        trees[index] = BVHTree.FromPolygons(points, model.pieces[index]["faces"])
    return trees[index]


def rest_points(rig, model):
    """The vertices in the bind pose: the rig's rest position, every clip off."""
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    points = model.points()
    rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    return points


def report(rig, meshes, tolerance=TOLERANCE):
    """For every clip, every frame: the most any part lifts off what it sits on, with the frame,
    the part and the piece it stays nearest, and the most any part sinks into it, likewise. A
    clip fails when a part lifts beyond `tolerance` or sinks beyond SINK. Returns
    (lines, passed); a model of one piece has nothing to check and passes."""
    model = Model(meshes)
    if len(model.pieces) < 2:
        return ["one piece: nothing to check"], True
    parts = model.anchor(rest_points(rig, model))
    lines = ["%d parts on the body, %d wisps left out" % (len(parts), len(model.wisps))]
    scene = bpy.context.scene
    passed = True
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        start, end = imported.play(rig, action)
        high, at = -float("inf"), None
        deep, sunk_at = -float("inf"), None
        for frame in range(start, end + 1):
            scene.frame_set(frame)
            points, trees = model.points(), {}
            for part in parts:
                grown, anchor = lift(model, part, points, trees)
                if grown > high:
                    high, at = grown, (frame, part["name"], anchor)
                sunk, anchor = sink(model, part, points, trees)
                if sunk > deep:
                    deep, sunk_at = sunk, (frame, part["name"], anchor)
        fails = high > tolerance or deep > SINK
        passed = passed and not fails
        lines.append("%s %s: max lift %.1f mm (frame %d, %s off %s); max sink %d %% (frame %d, %s into %s)" % (
            "FAIL" if fails else "ok", action.name, max(high, 0.0) * 1000, *at, round(max(deep, 0.0) * 100), *sunk_at))
    return lines, passed
