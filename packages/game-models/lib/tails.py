"""A beast's many tails (#1771): finding them on the mesh, rigging each as a chain of its own, moving
them in every clip, and checking all of it.

A generator's auto-rig gives a fan of tails one or two chains, whatever the count (the owner, on
#1771: "only two are rigged"), so the tails are read from the mesh, never from its bones:

- **find:** how far each vertex lies from the hips along the surface (a loose piece, the crystal on
  a tail's tip, hangs on the nearest skin). Sweeping that distance from far to near, every limb
  starts as a piece of its own around its tip, and it ends where it runs into another limb: a
  `Branch`. A fold shorter than `SHARE` of the model's height is no limb. A tail is a branch whose
  tip lies behind the model's middle and off the ground, which rules out the head and the legs.
- **rig:** `Fan` gives each tail `BONES` bones from its branch's base to its tip, through the middle
  of the skin at each distance, hung from the hips, and all of the branch's skin to them. Each
  bone's Z axis points back, so turning a bone about Z sways it within the fan and about X swings
  it fore and aft. What the tails grow out of stays with the hips.
- **move:** `Fan.move`, an overlay for clips.animate, turns every tail in every clip (MOTIONS), the
  wave running up each tail and across the fan, so no two tails move alike.
- **check:** `report`, for check_tails.py: there are as many tails as the model says, each moved by
  bones of its own, a bend of those moves only that tail, and it moves in every clip.

Blender is Z-up and the model faces -Y; its left is +X."""

import heapq
import math

import bpy
import numpy
from mathutils import Vector

from . import imported, scene

# A limb is at least this share of the model's height, from its tip to where it joins another.
SHARE = 0.3
# A tail's tip is off the ground by at least this share of the model's height.
OFF_GROUND = 0.1
# Positions this close (decimals, in metres) are one vertex: the export splits a vertex at a seam.
WELD = 4
# How many bones a tail gets, what share of a bone's length the skin blends over at a joint, and
# over how many bones from its base a tail's skin comes off the hips.
BONES = 5
JOINT = 0.35
ROOT = 0.5
# The last bone starts this share of the way along a tail's skin.
LAST = 0.85
# How many vertices give the middle of a tail's skin at a joint.
RING = 12

# --- What the check holds a tail to --------------------------------------------------------------
# A tail's far part, past this share of its length from its base: where nothing blends with the hips.
FAR = 0.25
# The share of the far part's vertices that its own bones must move most.
OWN = 0.95
# A bone counts as a tail's when it moves at least this share of its far part most.
HOLDS = 0.01
# A tail has at least this many bones of its own.
LEAST_BONES = 3
# A bend of a tail's first bone by this much (radians) moves its tip by at least MOVES of its length,
# and no other tail's skin by more than STAYS (metres).
BEND = math.radians(30.0)
MOVES = 0.2
STAYS = 0.005
# In every clip, a tail's tip moves against the hips by at least this share of its length.
CLIP_MOVES = 0.02


class Surface:
    """A mesh's vertices welded by position, with the edges between them, every loose piece bridged
    to the nearest vertex of the largest one. `weld[i]` is vertex i's welded index."""

    def __init__(self, points, edges):
        self.weld = numpy.zeros(len(points), dtype=int)
        seen = {}
        for index, point in enumerate(numpy.round(points, WELD)):
            self.weld[index] = seen.setdefault(tuple(point.tolist()), len(seen))
        self.points = numpy.zeros((len(seen), 3))
        self.points[self.weld] = points
        self.near = [{} for _ in seen]
        for first, second in edges:
            self._join(self.weld[first], self.weld[second])
        self._bridge()

    def _join(self, first, second):
        if first != second:
            length = float(numpy.linalg.norm(self.points[first] - self.points[second]))
            self.near[first][int(second)] = self.near[second][int(first)] = length

    def _pieces(self):
        piece = numpy.full(len(self.points), -1)
        count = 0
        for start in range(len(self.points)):
            if piece[start] >= 0:
                continue
            piece[start] = count
            stack = [start]
            while stack:
                for other in self.near[stack.pop()]:
                    if piece[other] < 0:
                        piece[other] = count
                        stack.append(other)
            count += 1
        return piece, count

    def _bridge(self):
        piece, count = self._pieces()
        largest = int(numpy.argmax(numpy.bincount(piece)))
        body = numpy.flatnonzero(piece == largest)
        self.loose = piece != largest
        for number in range(count):
            if number != largest:
                members = numpy.flatnonzero(piece == number)
                gaps = numpy.linalg.norm(self.points[members][:, None] - self.points[body][None], axis=2)
                first, second = numpy.unravel_index(int(gaps.argmin()), gaps.shape)
                self._join(members[first], body[second])

    def distances(self, start):
        """Every welded vertex's distance along the surface from the one nearest `start`."""
        origin = int(numpy.linalg.norm(self.points - numpy.array(start), axis=1).argmin())
        found = numpy.full(len(self.points), math.inf)
        found[origin] = 0.0
        queue = [(0.0, origin)]
        while queue:
            far, vertex = heapq.heappop(queue)
            if far > found[vertex]:
                continue
            for other, length in self.near[vertex].items():
                if far + length < found[other]:
                    found[other] = far + length
                    heapq.heappush(queue, (far + length, other))
        return found


class Branch:
    """A limb: its `tip` (a welded vertex), the distance `base` where it runs into another limb, and
    its welded vertices, `members`."""

    def __init__(self, tip, base, members):
        self.tip, self.base, self.members = tip, base, numpy.array(sorted(members))


def branches(surface, distance, shortest):
    """The limbs of `surface` by `distance` from the hips: every piece of at least `shortest` from
    its tip to where it meets another, cut off there (see the module's notes)."""
    parent = {}
    tips, members, hub = {}, {}, set()

    def top(vertex):
        while parent[vertex] != vertex:
            parent[vertex] = parent[parent[vertex]]
            vertex = parent[vertex]
        return vertex

    found = []
    for vertex in numpy.argsort(-distance, kind="stable").tolist():
        parent[vertex], tips[vertex], members[vertex] = vertex, vertex, [vertex]
        level = float(distance[vertex])
        for other in sorted(surface.near[vertex]):
            if other not in parent:
                continue
            first, second = top(vertex), top(other)
            if first == second:
                continue
            long_ = [piece for piece in (first, second)
                     if piece in hub or distance[tips[piece]] - level >= shortest]
            if len(long_) == 2:
                for piece in long_:
                    if piece not in hub:
                        found.append(Branch(tips[piece], level, members[piece]))
            # The longer piece's root stands for both.
            keep, drop = sorted((first, second), key=lambda piece: len(members[piece]), reverse=True)
            tip = tips[first] if distance[tips[first]] >= distance[tips[second]] else tips[second]
            is_hub = len(long_) == 2 or first in hub or second in hub
            parent[drop] = keep
            members[keep].extend(members.pop(drop))
            tips[keep] = tip
            hub.discard(drop)
            if is_hub:
                hub.add(keep)
    return found


def find(points, edges, hips):
    """The tails of a mesh at rest (`points` an (n, 3) array, `edges` pairs of vertices) whose hips
    stand at `hips`: (the Surface, every vertex's distance from the hips along it, its tails from
    its right (-X) to its left, up and over)."""
    surface = Surface(points, edges)
    distance = surface.distances(hips)
    height = float(surface.points[:, 2].max() - surface.points[:, 2].min())
    tails = [branch for branch in branches(surface, distance, SHARE * height)
             if surface.points[branch.tip][1] > 0.0 and surface.points[branch.tip][2] > OFF_GROUND * height]
    tails.sort(key=lambda branch: math.atan2(surface.points[branch.tip][0], surface.points[branch.tip][2]))
    return surface, distance, tails


def _points(skin):
    coordinates = numpy.empty(len(skin.data.vertices) * 3)
    skin.data.vertices.foreach_get("co", coordinates)
    return coordinates.reshape(-1, 3)


def _edges(skin):
    return [tuple(edge.vertices) for edge in skin.data.edges]


def _smooth(share):
    share = min(1.0, max(0.0, share))
    return share * share * (3.0 - 2.0 * share)


class Motion:
    """How a fan moves through one clip, each a function of how far through the clip it is (0..1):
    `ripple`, how far its waves swing a tail's tip (radians, over the whole tail, as the others);
    `waves`, how many run up it in the clip, a whole number on a
    loop; `back`, how far it leans back (toward +Y, less than nothing forward); `droop`, how far it
    sinks to the ground (each tail sways down, the middle one back; less than nothing raises it)."""

    def __init__(self, ripple, waves, back=lambda _t: 0.0, droop=lambda _t: 0.0):
        self.ripple, self.waves, self.back, self.droop = ripple, waves, back, droop


def _steady(value):
    return lambda _t: value


def _pose_to_pose(*keys):
    """A function through (t, value) keys, eased between them."""
    def at(t):
        for (start, first), (end, second) in zip(keys, keys[1:]):
            if t <= end:
                return first + (second - first) * _smooth((t - start) / (end - start))
        return keys[-1][1]
    return at


# How the tails move in each clip the game plays (lib/clip_set.py): a slow ripple at rest, swinging
# with the gait, streaming back in a run, drawn back and whipped forward with the bite, flung back
# by a blow, sinking to the ground as it falls or sleeps, and flared up behind a long attack.
MOTIONS = {
    "Idle": Motion(_steady(0.25), 2),
    "Walk": Motion(_steady(0.30), 1, _steady(0.10)),
    "Run": Motion(_steady(0.25), 1, _steady(0.25)),
    "Attack": Motion(_pose_to_pose((0.0, 0.08), (0.3, 0.30), (1.0, 0.08)), 2,
                     _pose_to_pose((0.0, 0.0), (0.22, 0.50), (0.42, -0.60), (0.62, 0.14), (1.0, 0.0))),
    "Hit": Motion(_pose_to_pose((0.0, 0.08), (0.2, 0.20), (1.0, 0.05)), 3,
                  _pose_to_pose((0.0, 0.0), (0.15, 0.08), (0.5, -0.10), (1.0, 0.0))),
    "Faint": Motion(_pose_to_pose((0.0, 0.20), (0.5, 0.08), (1.0, 0.03)), 2, _steady(0.0),
                    _pose_to_pose((0.0, 0.0), (0.7, 0.36), (1.0, 0.32))),
    "ChannelStart": Motion(_pose_to_pose((0.0, 0.10), (1.0, 0.22)), 1, _pose_to_pose((0.0, 0.0), (1.0, -0.25)),
                           _pose_to_pose((0.0, 0.0), (1.0, -0.25))),
    "Channel": Motion(_steady(0.22), 2, _steady(-0.25), _steady(-0.25)),
    "ChannelEnd": Motion(_pose_to_pose((0.0, 0.22), (1.0, 0.10)), 1, _pose_to_pose((0.0, -0.25), (1.0, 0.0)),
                         _pose_to_pose((0.0, -0.25), (1.0, 0.0))),
    "Feed": Motion(_steady(0.18), 1),
    "Sleep": Motion(_steady(0.11), 1, _steady(-0.30), _steady(0.08)),
}
# How far the wave lags from one bone up a tail to the next, and from one tail to the next across the
# fan (radians), and how much more of its share of the swing each bone up a tail takes.
UP_THE_TAIL = 0.75
ACROSS = 1.1
GROWS = 0.25
# A tail's fore-and-aft swing, against its sway within the fan.
FORE_AFT = 0.55


class Fan:
    """Every tail of `skin`, rigged on `rig` from its `hips` bone as a chain of `BONES` bones
    `tail_<tail>_<bone>`, numbered from its right (-X) to its left. It fails unless it finds `count`."""

    def __init__(self, rig, skin, count, hips="hips"):
        surface, distance, tails = find(_points(skin), _edges(skin), rig.data.bones[hips].head_local)
        if len(tails) != count:
            raise ValueError("expected %d tails, found %d" % (count, len(tails)))
        self.names = []
        joints = [self._joints(surface, distance, tail) for tail in tails]
        scene.select_only(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        edit = rig.data.edit_bones
        for number, points in enumerate(joints):
            names = []
            parent = edit[hips]
            for index in range(BONES):
                bone = edit.new("tail_%d_%02d" % (number + 1, index + 1))
                bone.head, bone.tail = Vector(points[index]), Vector(points[index + 1])
                bone.parent = parent
                bone.use_connect = index > 0
                bone.align_roll(Vector((0.0, 1.0, 0.0)))
                parent = bone
                names.append(bone.name)
            self.names.append(names)
        bpy.ops.object.mode_set(mode="OBJECT")
        # Which way down is for each tail, within the fan: the middle one has none.
        widest = max(abs(points[-1][0]) for points in joints)
        self.sides = [points[-1][0] / widest for points in joints]
        self._bind(skin, surface, distance, tails, hips)

    @staticmethod
    def _joints(surface, distance, tail):
        """A tail's joints: the middle of its skin at each of BONES even distances from its base to
        where its last bone starts (_span), then the tip itself."""
        skin = tail.members[~surface.loose[tail.members]]
        out = []
        for index in range(BONES):
            level = tail.base + Fan._span(surface, distance, tail) * index / (BONES - 1)
            # The vertices nearest that distance: a coarse mesh leaves no even ring.
            ring = skin[numpy.argsort(numpy.abs(distance[skin] - level), kind="stable")[:RING]]
            out.append(surface.points[ring].mean(axis=0).tolist())
        out.append(surface.points[tail.tip].tolist())
        return out

    @staticmethod
    def _span(surface, distance, tail):
        """How far along a tail its last bone starts: short of its skin's end, so the end of the skin
        and the piece on its tip move as one."""
        return LAST * (float(distance[tail.members[~surface.loose[tail.members]]].max()) - tail.base)

    def _bind(self, skin, surface, distance, tails, hips):
        """All of each tail's skin to its own bones, off whatever held it, blended at each joint and
        at its base with the hips; a loose piece on its tip stays whole, on its last bone."""
        owner = {}
        for number, tail in enumerate(tails):
            span = self._span(surface, distance, tail)
            for member in tail.members.tolist():
                along = (float(distance[member]) - tail.base) / span * (BONES - 1)
                owner[member] = (number, BONES - 0.5 if surface.loose[member] else min(along, BONES - 1e-6))
        for index, welded in enumerate(surface.weld.tolist()):
            if welded not in owner:
                continue
            for group in [element.group for element in skin.data.vertices[index].groups]:
                skin.vertex_groups[group].remove([index])
            number, along = owner[welded]
            for name, weight in self._shares(number, along, hips).items():
                group = skin.vertex_groups.get(name) or skin.vertex_groups.new(name=name)
                group.add([index], weight, "REPLACE")

    def _shares(self, number, along, hips):
        """The bones at `along` (in bones from its base) up tail `number`, and how much each holds."""
        bone = int(along)
        within = along - bone
        names = self.names[number]
        out = {names[bone]: 1.0}
        if along < ROOT:
            return {hips: 1.0 - _smooth(along / ROOT), names[0]: _smooth(along / ROOT)}
        if within > 1.0 - JOINT / 2.0 and bone + 1 < BONES:
            share = _smooth((within - 1.0 + JOINT / 2.0) / JOINT)
            out = {names[bone]: 1.0 - share, names[bone + 1]: share}
        elif within < JOINT / 2.0 and bone > 0:
            share = _smooth((within + JOINT / 2.0) / JOINT)
            out = {names[bone - 1]: 1.0 - share, names[bone]: share}
        return out

    def move(self, name, poses, loop):
        """An overlay for clips.animate: turns every tail through clip `name` (MOTIONS)."""
        motion = MOTIONS[name]
        last = max(1, len(poses) - 1)
        for step, (_frame, pose) in enumerate(poses):
            t = step / last
            lap = 2.0 * math.pi * motion.waves * t
            ripple, back, droop = motion.ripple(t), motion.back(t), motion.droop(t)
            for number, names in enumerate(self.names):
                side = self.sides[number]
                for index, bone in enumerate(names):
                    wave = lap - UP_THE_TAIL * index - ACROSS * number
                    swing = ripple * (1.0 + GROWS * (index - (BONES - 1) / 2.0)) / BONES
                    pose[bone] = ((back + droop * (1.0 - abs(side))) / BONES + FORE_AFT * swing * math.cos(wave), 0.0,
                                  droop * side / BONES + swing * math.sin(wave))


# --- The check ----------------------------------------------------------------------------------


def _skinned(objects, rig):
    shapes = {bone.custom_shape for bone in rig.pose.bones if bone.custom_shape is not None}
    meshes = [obj for obj in objects if obj.type == "MESH" and obj not in shapes]
    return max(meshes, key=lambda obj: len(obj.data.vertices))


def _deformed(skin):
    """`skin`'s vertices as posed now, an (n, 3) array in world space."""
    evaluated = skin.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    coordinates = numpy.empty(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", coordinates)
    evaluated.to_mesh_clear()
    world = numpy.array(evaluated.matrix_world)
    return coordinates.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]


def _strongest(skin):
    """Each vertex's bone that moves it most (None for one that no bone moves)."""
    names = {group.index: group.name for group in skin.vertex_groups}
    return [names[max(vertex.groups, key=lambda element: (element.weight, -element.group)).group]
            if len(vertex.groups) else None for vertex in skin.data.vertices]


class _Tail:
    """What the check knows of one tail: its `vertices` (of the skin), the `far` ones, its `tip` (a
    vertex), its `length`, and the `bones` found to be its own."""

    def __init__(self, surface, distance, branch):
        reach = float(distance[branch.tip]) - branch.base
        chosen = set(branch.members.tolist())
        cut = branch.base + FAR * reach
        self.vertices = numpy.array([index for index, welded in enumerate(surface.weld.tolist()) if welded in chosen])
        self.far = self.vertices[distance[surface.weld[self.vertices]] >= cut]
        self.tip = int(numpy.flatnonzero(surface.weld == branch.tip)[0])
        self.length = reach
        self.bones = []


def _own_bones(tails, strongest):
    """Fills each tail's `bones`: those moving its far part most that move no other tail's. Returns
    {tail number: {bone: share of its far part it moves most}}."""
    holds = {}
    for number, tail in enumerate(tails):
        counts = {}
        for index in tail.far.tolist():
            counts[strongest[index]] = counts.get(strongest[index], 0) + 1
        holds[number] = {bone: count / len(tail.far) for bone, count in counts.items()
                         if bone is not None and count / len(tail.far) >= HOLDS}
    for number, tail in enumerate(tails):
        others = {bone for other, held in holds.items() if other != number for bone in held}
        tail.bones = sorted(bone for bone in holds[number] if bone not in others)
    return holds


def _bent(rig, skin, tails, number):
    """Bends the lowest of the bones tail `number` counts as its own: how far its tip moves, and the most any other tail's
    skin moves."""
    tail = tails[number]
    chain = {bone.name: bone for bone in rig.pose.bones if bone.name in tail.bones}
    first = min(chain.values(), key=lambda bone: len(bone.parent_recursive))
    rest = _deformed(skin)
    mode = first.rotation_mode
    first.rotation_mode = "XYZ"
    first.rotation_euler = (BEND, 0.0, 0.0)
    bpy.context.view_layer.update()
    moved = numpy.linalg.norm(_deformed(skin) - rest, axis=1)
    first.rotation_euler = (0.0, 0.0, 0.0)
    first.rotation_mode = mode
    bpy.context.view_layer.update()
    others = [other.vertices for index, other in enumerate(tails) if index != number]
    return float(moved[tail.tip]), float(moved[numpy.concatenate(others)].max()) if others else 0.0


def _clip_moves(rig, skin, tails, action, hips):
    """How far each tail's tip moves against the hips through `action`, at most."""
    tips = numpy.array([tail.tip for tail in tails])
    start, end = imported.play(rig, action)
    found = []
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        into = numpy.array((rig.matrix_world @ rig.pose.bones[hips].matrix).inverted())
        at = _deformed(skin)[tips]
        found.append(at @ into[:3, :3].T + into[:3, 3])
    found = numpy.array(found)
    return numpy.linalg.norm(found - found[0], axis=2).max(axis=0) if len(found) else numpy.zeros(len(tails))


def report(rig, objects, count, hips="hips"):
    """(lines, passed): whether the model has `count` tails, each rigged and moving on its own (see
    the module's notes). A failing line starts with FAIL."""
    if hips not in rig.data.bones:
        return ["FAIL no %s bone to measure its tails from" % hips], False
    skin = _skinned(objects, rig)
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    rest = numpy.array(_deformed(skin))
    surface, distance, branches_ = find(rest, _edges(skin), rig.matrix_world @ rig.data.bones[hips].head_local)
    if len(branches_) != count:
        return ["FAIL found %d tails on the mesh, expected %d" % (len(branches_), count)], False
    tails = [_Tail(surface, distance, branch) for branch in branches_]
    lines, passed = [], True
    strongest = _strongest(skin)
    holds = _own_bones(tails, strongest)
    rig.data.pose_position = "POSE"
    rig.animation_data_create()
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    for bone in rig.pose.bones:
        bone.location, bone.scale = (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)
        bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    for number, tail in enumerate(tails):
        label = "tail %d (tip %.2f, %.2f, %.2f)" % (number + 1, *rest[tail.tip])
        share = sum(holds[number].get(bone, 0.0) for bone in tail.bones)
        if share < OWN or len(tail.bones) < LEAST_BONES:
            passed = False
            shared = sorted(bone for bone in holds[number] if bone not in tail.bones)
            lines.append("FAIL %s: unrigged: %d bones of its own move %.0f%% of it (needs %d and %.0f%%); shared: %s" % (
                label, len(tail.bones), 100.0 * share, LEAST_BONES, 100.0 * OWN, ", ".join(shared) or "none"))
            continue
        moved, others = _bent(rig, skin, tails, number)
        if moved < MOVES * tail.length or others > STAYS:
            passed = False
            lines.append("FAIL %s: a bend of %s moves its tip %.3f m (needs %.3f) and another tail %.3f m (at most %.3f)" % (
                label, tail.bones[0], moved, MOVES * tail.length, others, STAYS))
            continue
        lines.append("ok %s: %d bones of its own, %.0f%% of it; a bend moves its tip %.3f m, the others %.3f m" % (
            label, len(tail.bones), 100.0 * share, moved, others))
    actions = sorted(bpy.data.actions, key=lambda action: action.name)
    if not actions:
        passed = False
        lines.append("FAIL no clips to move its tails in")
    for action in actions:
        far = _clip_moves(rig, skin, tails, action, hips)
        still = [number + 1 for number, tail in enumerate(tails) if far[number] < CLIP_MOVES * tail.length]
        if still:
            passed = False
            lines.append("FAIL %s: tails %s don't move (at least %.0f%% of a tail's length)" % (
                action.name, ", ".join(map(str, still)), 100.0 * CLIP_MOVES))
        else:
            lines.append("ok %s: every tail moves, the least %.3f m" % (action.name, float(far.min())))
    return lines, passed
