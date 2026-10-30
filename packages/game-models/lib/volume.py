"""Volume (#1306): how thick the body stays where the spine and neck bend, for check_volume.py.
The owner, on #1305: "the upper body gets very slim at a certain point while it bends down".
Skinning that blends two bones linearly pulls the skin on the inside and outside of a bend
toward the bone (the "candy wrapper" of a twist, the pinch of a fold), so a creature bowing its
head or arching its back loses girth exactly there.

A **station** is a point on the spine or neck (STATIONS: a bone and a share along it); its cross
section is the plane through it square to the bone there, the bisector of two bones at a joint
(share 0 with the bone's parent, share 1 with its child). From the station, rays in that plane
run out to the body's skin (`body`: the parts joined into it don't count): up and down give the
body's **depth** there, side to side its **width**. Up and the side turn with the bone (its
rotation from rest), so the cross section follows the body however it bends. Each is measured at
rest (the bind pose) and in every frame of every clip, and a clip fails when one falls below
SHARE of its rest value.

SHARE: a bend that keeps the body's volume moves a cross section only a little either way, as
the skin bunches on the bend's inner side and stretches on its outer; the clips that bend least
(the idle, the channel) stay well above the limit. The thinning the owner saw takes well over a
fifth away, the throat's or the chest's underside drawn up toward the spine. A fifth lost is the
limit: past it the body reads as thinner, not as bent."""

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from . import imported

# (bone, share along it) for every station, from the hips forward; share 0 is the joint with the
# bone's parent, 1 the joint with its child (CHILD). A rig without a station's bones skips it.
STATIONS = (
    ("spine_01", 0.5),
    ("spine_02", 0.0),
    ("spine_02", 0.5),
    ("neck", 0.0),
    ("neck", 0.5),
    ("neck", 1.0),
)
# The bone each station's bone continues into, for its share-1 joint.
CHILD = {"spine_01": "spine_02", "spine_02": "neck", "neck": "head"}
# The share of its rest depth and width a cross section must keep in every frame.
SHARE = 0.8
# How far a ray reaches (metres): past any body the game has, short of anything around it.
REACH = 2.0


def _matrix(rig, name):
    """The bone `name`'s matrix in the world, in the rig's current pose."""
    return rig.matrix_world @ rig.pose.bones[name].matrix


def _rest(rig, name):
    return rig.matrix_world @ rig.data.bones[name].matrix_local


def _ends(rig, name, rest):
    """The bone's head and tail in the world, at rest or posed (a rest bone's own head and tail
    are its parent's space; its `_local` ones are the armature's, as a posed bone's are)."""
    world = rig.matrix_world
    if rest:
        bone = rig.data.bones[name]
        return world @ bone.head_local, world @ bone.tail_local
    bone = rig.pose.bones[name]
    return world @ bone.head, world @ bone.tail


def _direction(rig, name, rest):
    head, tail = _ends(rig, name, rest)
    return (tail - head).normalized()


def frame(rig, station, rest=False):
    """The station's centre and its cross section's axes (along, up, side) in the world, at rest
    or in the rig's current pose. The side is the world's X at rest (the creature faces along Y,
    upright on Z), turned with the bone, and up is square to it and the bone: the world's Z for a
    level bone, the bone's back for an upright one."""
    name, share = station
    bone = rig.data.bones[name]
    head, tail = _ends(rig, name, rest)
    centre = head.lerp(tail, share)
    along = _direction(rig, name, rest)
    neighbour = None
    if share == 0.0 and bone.parent is not None:
        neighbour = bone.parent.name
    elif share == 1.0:
        neighbour = CHILD.get(name)
    if neighbour is not None:
        along = (along + _direction(rig, neighbour, rest)).normalized()
    # The bone's turn from rest, which carries the world's up with it, laid into the cross
    # section's plane, whose normal at a joint isn't the bone's.
    # Only its rotation: a bone's scale (a pulsing part's parent) mustn't skew the axes.
    turn = Matrix.Identity(3) if rest else (_matrix(rig, name).to_quaternion()
                                            @ _rest(rig, name).to_quaternion().inverted()).to_matrix()
    # The side comes first, from the world's X: an upright bone (a neck rising to the head) runs
    # almost along the world's up, whose remainder in the plane points anywhere and swings round
    # the bone as the head nods (#1680), while no spine or neck bone runs along the side.
    side = turn @ Vector((1.0, 0.0, 0.0))
    side = (side - along * side.dot(along)).normalized()
    return centre, along, along.cross(side).normalized(), side


def body(meshes):
    """The body's skin: the largest piece of connected faces among the skinned meshes, by area,
    and that mesh, its vertices at one spot joined. The parts joined into the skin (crystals, a ruff, the jaw) are pieces of their own whose
    faces lie partly inside the body, where a ray from a station would stop on them."""
    best = (0.0, None, [])
    for obj in meshes:
        polygons = obj.data.polygons
        parent = list(range(len(obj.data.vertices)))

        def find(index):
            while parent[index] != index:
                parent[index] = parent[parent[index]]
                index = parent[index]
            return index

        # The export splits a vertex where its UVs part (a textured model's seams, #1476): the
        # corners at one spot are one vertex of the skin.
        spots = {}
        for vertex in obj.data.vertices:
            same = spots.setdefault(tuple(vertex.co), vertex.index)
            parent[find(vertex.index)] = find(same)
        for polygon in polygons:
            first = find(polygon.vertices[0])
            for index in polygon.vertices[1:]:
                parent[find(index)] = first
        pieces, areas = {}, {}
        for polygon in polygons:
            piece = find(polygon.vertices[0])
            pieces.setdefault(piece, []).append(list(polygon.vertices))
            areas[piece] = areas.get(piece, 0.0) + polygon.area * obj.matrix_world.median_scale ** 2
        piece = max(areas, key=areas.get, default=None)
        if piece is not None and areas[piece] > best[0]:
            best = (areas[piece], obj, pieces[piece])
    return best[1], best[2]


def _tree(skin):
    """The body's skin where the scene's current frame poses it, for ray casts."""
    obj, faces = skin
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    world = evaluated.matrix_world
    points = [world @ vertex.co for vertex in mesh.vertices]
    evaluated.to_mesh_clear()
    return BVHTree.FromPolygons(points, faces)


def _reaches(tree, centre, directions):
    """How far each ray from `centre` runs to the skin; None where it meets none."""
    hits = [tree.ray_cast(centre, direction, REACH) for direction in directions]
    return [None if hit[0] is None else hit[3] for hit in hits]


def measure(rig, skin, stations, rest=False):
    """Per station: (depth, width) in metres of `skin` (body), at rest or in the current pose, or
    None where a ray meets no skin: the station lies outside the body. Posed, that ray counts as
    nothing, a body thinned through to its bone."""
    tree = _tree(skin)
    found = {}
    for station in stations:
        centre, _along, up, side = frame(rig, station, rest)
        reaches = _reaches(tree, centre, (up, -up, side, -side))
        if rest and None in reaches:
            found[station] = None
            continue
        reaches = [0.0 if reach is None else reach for reach in reaches]
        found[station] = (reaches[0] + reaches[1], reaches[2] + reaches[3])
    return found


def name(station):
    return "%s@%.2f" % station


def rest_measure(rig, skin, stations):
    """Each station's depth and width in the bind pose: the rig's rest position, every clip off."""
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    found = measure(rig, skin, stations, rest=True)
    rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    return found


def report(rig, meshes, share=SHARE):
    """For every clip, every frame: the smallest share of its rest depth or width any station
    keeps, with the frame, the station and which of the two. A clip fails below `share`. Returns
    (lines, passed); a rig without spine or neck bones has nothing to check and passes."""
    stations = [s for s in STATIONS if s[0] in rig.pose.bones and (s[1] < 1.0 or CHILD[s[0]] in rig.pose.bones)]
    if not stations:
        return ["no spine or neck bones: nothing to check"], True
    skin = body(meshes)
    if skin[0] is None:
        return ["no skinned mesh: nothing to check"], True
    rest = rest_measure(rig, skin, stations)
    empty = [name(s) for s in stations if rest[s] is None]
    if empty:
        return ["FAIL stations outside the body at rest: " + ", ".join(empty)], False
    lines = ["rest %s: depth %.1f cm, width %.1f cm" % (name(s), rest[s][0] * 100, rest[s][1] * 100)
             for s in stations]
    scene = bpy.context.scene
    passed = True
    for action in sorted(bpy.data.actions, key=lambda a: a.name):
        start, end = imported.play(rig, action)
        low, at = float("inf"), None
        for number in range(start, end + 1):
            scene.frame_set(number)
            for station, (depth, width) in measure(rig, skin, stations).items():
                for what, value, base in (("depth", depth, rest[station][0]), ("width", width, rest[station][1])):
                    if value / base < low:
                        low, at = value / base, (number, name(station), what)
        fails = low < share
        passed = passed and not fails
        lines.append("%s %s: min %.0f%% of rest (frame %d, %s %s)" % (
            "FAIL" if fails else "ok", action.name, low * 100, *at))
    return lines, passed
