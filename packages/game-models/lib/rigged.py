"""Adopts the rig a generated model arrives with (#1516): the generator's first rigging pass, a
skinned mesh on chains of numbered bones, made into one the library's clips and checks can use.

`adopt` reads the rig's chains (bones in a row, split where a bone has more than one child) and
the mesh's parts (the pieces left once a ball around every fork is cut away, so each leg or
stalk is one piece). Each part belongs to the chain whose joints lie nearest it, and two things
are fixed there:

- **a short chain**: its part reaches well past its farthest joint, so most of the part can't
  bend. It is regrown: as many bones as its sibling chains have, laid through the part's middle,
  and the part is weighted to them by how near each lies.
- **a bleed**: another limb's chain holds weights in the part, so bending that limb drags this
  part along. Those weights go, and what's left is the part's own.
- **a turned-back end** (#1539): the generator ends a chain with bones that turn back on it (a
  leg's last bones climb back up from its sole, a stalk's come back down from its tip), holding
  few weights. Their weights go to the bone before them, and they go. So does an **empty end**
  (#1619): a last bone that weighs almost none of its part (a leg's toe bone reaching below the
  sole), so the bone holding the end becomes the paw.
- **a shared piece** (#1619): where a long trunk runs between two forks, its belly joins every
  leg below it into one piece; it is split into one part per chain by the weights (`split`).

**Mirror twins** (#1725), a left and a right chain hanging from the same chain, each the other
mirrored across X, are fixed alike: a part of the mesh is one twin's only if its twin has one too
(two ears on one head piece give that piece to neither), a loose end is folded only if both
twins' are, and a short chain is regrown only where its twin goes (its new tip's direction is its
twin's, mirrored). A short chain whose regrown bones would weigh almost none of its part (the body
holds it) isn't regrown either: it is reported, to rig by hand.

Vertices inside a fork's ball keep their weights: that's where the parts blend into the body.
Then every bone is named to the library's scheme by what its chain moves (`<pair>_leg_NN.<side>`
ending in `<pair>_paw.<side>`, which the clips plant; `<pair>_thigh.L` for a three-bone leg as the
hexapod has; `<pair>_stalk_NN.<side>`; `hips` and `spine_NN` for the trunk),
rolled as the library's armatures are (quadruped.build), and hung from a new `root` on the ground
between the feet, which the clips move. It prints what it kept, fixed and renamed.

Blender is Z-up and the model faces -Y; a part's left is +X."""

import math
import statistics
from collections import Counter

import bpy
from mathutils import Matrix, Vector
from mathutils.geometry import intersect_point_line

from . import scene

# A weight above this from another limb's chain counts as that chain reaching into the part.
BLEED = 0.1
# A piece of the mesh with less than this share of its vertices isn't a part (a stray bit at a
# fork's edge): it keeps its weights.
SMALL_PART = 0.01
# A chain is short when its part reaches past its farthest joint by more than this share of the
# part's reach from the fork.
SHORT = 0.25
# A part whose lowest point is this share of the model's height off the ground or less stands
# on it: a leg.
GROUND = 0.05
# A part whose middle is this share of the model's half width from the midline or less is in
# the middle, with no side.
MIDLINE = 0.25
# Its legs or stalks on one side, front to back, by how many there are.
PAIRS = {2: ("front", "hind"), 3: ("front", "mid", "hind")}
# A three-bone leg takes the hexapod's names, so its gaits and checks apply as they are.
LEG_PARTS = ("thigh", "shin", "paw")
# A bone turning from the one before it by more than this (radians) turns back on the chain.
TURNED_BACK = math.pi / 2
# A chain's last bone that weighs most fewer than this share of its part's vertices is an empty end.
EMPTY_END = 0.1
# Two chains are mirror twins when their joints, one side's mirrored across X, lie this share of
# the model's height apart or less on average.
TWIN = 0.05
# A regrown chain goes its twin's way when its tip's direction from its start turns from its twin's,
# mirrored, by this much (radians) or less.
TWIN_TURN = math.pi / 4
# The root the clips move: on the ground between the feet, pointing up, deforming nothing.
ROOT_LENGTH = 0.3


class Chain:
    """Bones in a row (names, the end nearest the root first) and the chain they hang from."""

    def __init__(self, bones, parent):
        self.bones = bones
        self.parent = parent
        self.part = None
        self.name = "%s..%s" % (bones[0], bones[-1]) if len(bones) > 1 else bones[0]

    def ancestors(self):
        chain, out = self.parent, []
        while chain is not None:
            out.append(chain)
            chain = chain.parent
        return out


class Part:
    """A piece of the mesh: its vertex indices and the fork it grows from (centre, radius)."""

    def __init__(self, vertices, fork):
        self.vertices = vertices
        self.fork = fork
        self.chain = None


def chains(rig):
    out = []

    def walk(bone, parent):
        names = [bone.name]
        while len(bone.children) == 1:
            bone = bone.children[0]
            names.append(bone.name)
        chain = Chain(names, parent)
        out.append(chain)
        for child in sorted(bone.children, key=lambda child: child.name):
            walk(child, chain)

    for root in sorted((bone for bone in rig.data.bones if bone.parent is None), key=lambda bone: bone.name):
        walk(root, None)
    return out


def children(chain, every):
    return [other for other in every if other.parent is chain]


def forks(every, bones):
    """(centre, radius) for every fork: the end of a chain with more than one chain below it, its
    ball reaching to where the chains below it have their first joint."""
    out = []
    for chain in every:
        below = children(chain, every)
        if len(below) < 2:
            continue
        # A copy: regrow's edit mode reallocates the bones, and a wrapped vector would go stale.
        centre = bones[chain.bones[-1]].tail_local.copy()
        out.append((centre, statistics.median((bones[other.bones[0]].tail_local - centre).length for other in below)))
    return out


def parts(skin, balls):
    """The pieces of the mesh outside every fork's ball. A seam splits a vertex into several at one
    spot, so the pieces are joined through spots, not vertex indices."""
    spot = {vertex.index: tuple(round(value, 5) for value in vertex.co) for vertex in skin.data.vertices}
    near = {}
    for edge in skin.data.edges:
        first, second = spot[edge.vertices[0]], spot[edge.vertices[1]]
        near.setdefault(first, set()).add(second)
        near.setdefault(second, set()).add(first)
    outside = {point for point in set(spot.values()) if all((Vector(point) - centre).length >= radius
                                                            for centre, radius in balls)}
    pieces, seen = [], set()
    for start in sorted(outside):
        if start in seen:
            continue
        seen.add(start)
        stack, piece = [start], set()
        while stack:
            point = stack.pop()
            piece.add(point)
            for other in near.get(point, ()):
                if other in outside and other not in seen:
                    seen.add(other)
                    stack.append(other)
        pieces.append(piece)
    out = []
    for piece in pieces:
        vertices = sorted(index for index, point in spot.items() if point in piece)
        if len(vertices) < SMALL_PART * len(spot):
            continue
        fork = min(balls, key=lambda ball: min((Vector(point) - ball[0]).length for point in piece) - ball[1])
        out.append(Part(vertices, fork))
    return out


def _dominant(skin, leaves):
    """{vertex index: the leaf chain whose bone weighs it most}, for vertices a leaf chain's bone
    weighs most."""
    owner = {name: chain for chain in leaves for name in chain.bones}
    names = {group.index: group.name for group in skin.vertex_groups}
    out = {}
    for vertex in skin.data.vertices:
        if vertex.groups:
            chain = owner.get(names[max(vertex.groups, key=lambda group: group.weight).group])
            if chain is not None:
                out[vertex.index] = chain
    return out


def split(found, leaves, skin, bones, balls):
    """Splits a piece that several leaf chains call home (#1619): where a long trunk runs between
    two forks, its belly joins every leg below it into one piece outside the forks' balls. A
    chain's home is the piece holding most of the vertices its bones weigh most; a piece that is
    home to two chains or more becomes one part per chain, the vertices that chain weighs most,
    each growing from the fork its chain hangs from. The piece's other vertices (the trunk's)
    keep their weights. A piece one chain calls home stays whole, whatever weights reach into
    it: those are bleeds, fixed in adopt."""
    dominant = _dominant(skin, leaves)
    homes = {}
    for chain in leaves:
        mine = {index for index, owner in dominant.items() if owner is chain}
        counts = [(len(mine.intersection(part.vertices)), index) for index, part in enumerate(found)]
        if counts and max(counts)[0] > 0:
            homes.setdefault(max(counts)[1], []).append(chain)
    out = []
    for index, part in enumerate(found):
        chains_ = homes.get(index, [])
        if len(chains_) < 2:
            out.append(part)
            continue
        for chain in chains_:
            vertices = sorted(vertex for vertex in part.vertices if dominant.get(vertex) is chain)
            start = bones[chain.parent.bones[-1]].tail_local if chain.parent is not None else part.fork[0]
            fork = min(balls, key=lambda ball: (ball[0] - start).length)
            piece = Part(vertices, fork)
            piece.chain, chain.part = chain, piece
            out.append(piece)
        print("SPLIT a piece of %d vertices that %d chains call home into their parts: %s"
              % (len(part.vertices), len(chains_), ", ".join(chain.name for chain in chains_)))
    return out


def _joints(chain, bones):
    return [bones[chain.bones[0]].head_local] + [bones[name].tail_local for name in chain.bones]


def match(leaves, found, skin, bones):
    """Gives each part the leaf chain whose joints lie nearest it on average, one chain a part,
    nearest pairs first."""
    points = {id(part): [skin.data.vertices[index].co for index in part.vertices] for part in found}
    pairs = []
    for chain in leaves:
        joints = _joints(chain, bones)
        for part in found:
            gap = sum(min((joint - point).length for point in points[id(part)]) for joint in joints) / len(joints)
            pairs.append((gap, chain.name, chain, part))
    for _gap, _name, chain, part in sorted(pairs, key=lambda pair: pair[:2]):
        if chain.part is None and part.chain is None:
            chain.part, part.chain = part, chain


def reach(part, skin):
    centre = part.fork[0]
    return max((skin.data.vertices[index].co - centre).length for index in part.vertices)


def is_short(chain, skin, bones):
    centre = chain.part.fork[0]
    joints = max((joint - centre).length for joint in _joints(chain, bones))
    whole = reach(chain.part, skin)
    return whole - joints > SHORT * whole, joints, whole


def _weights(skin):
    """{vertex index: {group name: weight}}."""
    names = {group.index: group.name for group in skin.vertex_groups}
    return {vertex.index: {names[group.group]: group.weight for group in vertex.groups if group.weight > 0.0}
            for vertex in skin.data.vertices}


def _set_weights(skin, index, weights):
    for group in skin.vertex_groups:
        group.remove([index])
    for name, weight in weights.items():
        if weight > 0.0:
            (skin.vertex_groups.get(name) or skin.vertex_groups.new(name=name)).add([index], weight, "REPLACE")


def _middle(skin, indices):
    return sum((skin.data.vertices[index].co for index in indices), Vector()) / len(indices)


def regrown_joints(skin, chain, count):
    """Where `count` bones regrown through `chain`'s part's middle end: each at the middle of the
    next band of the part (by distance from its fork), the last at its far end."""
    part = chain.part
    centre = part.fork[0]
    far = {index: (skin.data.vertices[index].co - centre).length for index in part.vertices}
    low, high = min(far.values()), max(far.values())
    width = (high - low) / count
    joints = []
    for band in range(count - 1):
        inside = [index for index, distance in far.items() if low + band * width <= distance < low + (band + 1) * width]
        # A band with no vertex (a sparse part) takes the nearest vertex to its middle distance.
        inside = inside or [min(far, key=lambda index: abs(far[index] - low - (band + 0.5) * width))]
        joints.append(_middle(skin, inside))
    joints.append(_middle(skin, [index for index, distance in far.items() if distance >= high - width / 4]))
    return joints


def regrow(rig, skin, chain, joints):
    """Replaces `chain`'s bones with bones ending at `joints` (regrown_joints), the first from where
    the chain starts. Weights the old bones held outside the part, inside the fork's ball, go to
    the bone the chain hangs from: there the body is moved, not the part. Returns the new bones'
    names."""
    part = chain.part
    count = len(joints)
    old = list(chain.bones)
    new = ["%s_regrown_%02d" % (old[0], number + 1) for number in range(count)]
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = rig.data.edit_bones
    head = Vector(edit[old[0]].head)
    parent = edit[old[0]].parent
    body = parent.name if parent is not None else new[0]
    for name, tail in zip(new, joints):
        bone = edit.new(name)
        bone.head, bone.tail, bone.parent = head, tail, parent
        bone.use_connect = parent is not None and (Vector(parent.tail) - head).length < 1e-4
        head, parent = tail, bone
    for name in old:
        edit.remove(edit[name])
    bpy.ops.object.mode_set(mode="OBJECT")
    inside = set(part.vertices)
    for index, weights in _weights(skin).items():
        if index in inside:
            continue
        moved = sum(weights.pop(name, 0.0) for name in old)
        if moved > 0.0:
            weights[body] = weights.get(body, 0.0) + moved
            _set_weights(skin, index, weights)
    for name in old:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    chain.bones = new
    return new


def _nearest(point, chain, bones, count=2):
    """`point`'s weights on the `count` bones of `chain` nearest it, by an inverse sixth power of
    the distance (as hexapod.bind weights its legs), adding up to 1."""
    pulls = []
    for name in chain.bones:
        head, tail = bones[name].head_local, bones[name].tail_local
        along = max(0.0, min(1.0, intersect_point_line(point, head, tail)[1]))
        pulls.append((1.0 / ((point - head.lerp(tail, along)).length + 1e-3) ** 6, name))
    pulls = sorted(pulls, reverse=True)[:count]
    whole = sum(pull for pull, _name in pulls)
    return {name: pull / whole for pull, name in pulls}


def _named(skin, index):
    return {skin.vertex_groups[group.group].name: group.weight
            for group in skin.data.vertices[index].groups if group.weight > 0.0}


def bleeds(skin, chain, leaves):
    """How many of `chain`'s part's vertices hold another limb's weight above BLEED, by chain."""
    others = {name: other.name for other in leaves if other is not chain for name in other.bones}
    bled = Counter()
    for index in chain.part.vertices:
        held = _named(skin, index)
        for other in {others[name] for name, weight in held.items() if name in others and weight > BLEED}:
            bled[other] += 1
    return bled


def reweight(skin, chain, bones, regrown):
    """Keeps only `chain`'s weights and those of the chains it hangs from in its part. A regrown
    chain's share is laid anew by where each vertex lies; otherwise what's left is scaled back
    up to the whole."""
    own, body = set(chain.bones), {name for other in chain.ancestors() for name in other.bones}
    for index in chain.part.vertices:
        kept = {name: weight for name, weight in _named(skin, index).items()
                if name in body or (name in own and not regrown)}
        base = sum(weight for name, weight in kept.items() if name in body)
        if regrown or not any(name in own for name in kept) or base >= 1.0:
            kept = {name: weight for name, weight in kept.items() if name in body}
            share = max(0.0, 1.0 - base)
            for name, weight in _nearest(skin.data.vertices[index].co, chain, bones).items():
                kept[name] = weight * share
        else:
            whole = sum(kept.values())
            kept = {name: weight / whole for name, weight in kept.items()}
        _set_weights(skin, index, kept)


def turned_back(chain, bones):
    """How many bones at the end of `chain` turn back on it: from the last bone turning by more
    than TURNED_BACK from the one before it, to the end. Fewer than half the chain's: a chain
    folding back on itself in its middle is a shape (a curl), not a generator's loose end."""
    directions = [(bones[name].tail_local - bones[name].head_local).normalized() for name in chain.bones]
    for index in range(len(directions) - 1, 0, -1):
        if directions[index].angle(directions[index - 1], 0.0) > TURNED_BACK:
            count = len(directions) - index
            return count if 2 * count < len(directions) else 0
    return 0


def empty_end(chain, skin):
    """Whether `chain`'s last bone weighs most fewer than EMPTY_END of its part's vertices."""
    last = skin.vertex_groups.get(chain.bones[-1])
    if last is None:
        return True
    held = sum(1 for index in chain.part.vertices
               if skin.data.vertices[index].groups
               and max(skin.data.vertices[index].groups, key=lambda group: group.weight).group == last.index)
    return held < EMPTY_END * len(chain.part.vertices)


def fold(rig, skin, chain, count):
    """Drops `chain`'s last `count` bones, their weights going to the bone before them."""
    dropped, kept = chain.bones[-count:], chain.bones[-count - 1]
    for index, weights in _weights(skin).items():
        moved = sum(weights.pop(name, 0.0) for name in dropped)
        if moved > 0.0:
            weights[kept] = weights.get(kept, 0.0) + moved
            _set_weights(skin, index, weights)
    for name in dropped:
        if skin.vertex_groups.get(name):
            skin.vertex_groups.remove(skin.vertex_groups[name])
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name in dropped:
        rig.data.edit_bones.remove(rig.data.edit_bones[name])
    bpy.ops.object.mode_set(mode="OBJECT")
    chain.bones = chain.bones[:-count]


def _mirrored(point):
    return Vector((-point.x, point.y, point.z))


def twins(leaves, skin, bones):
    """{chain: its mirror twin}: two leaf chains off the same chain whose starts and tips mirror
    each other across X within TWIN of the model's height, off the midline. Their bone counts
    may differ: the generator doesn't always give both sides as many."""
    heights = [vertex.co.z for vertex in skin.data.vertices]
    near = TWIN * (max(heights) - min(heights))
    pairs = []
    for first in leaves:
        for second in leaves:
            if first.name >= second.name or first.parent is not second.parent:
                continue
            ours, theirs = _joints(first, bones)[::len(first.bones)], _joints(second, bones)[::len(second.bones)]
            if sum(abs(joint.x) for joint in ours) / len(ours) <= near:
                continue
            gap = sum((_mirrored(joint) - other).length for joint, other in zip(ours, theirs)) / len(ours)
            if gap <= near:
                pairs.append((gap, first.name, second.name, first, second))
    out = {}
    for _gap, _first, _second, first, second in sorted(pairs, key=lambda pair: pair[:3]):
        if first not in out and second not in out:
            out[first], out[second] = second, first
    return out


def _direction(start, joints):
    return (joints[-1] - start).normalized()


def _held(skin, chain):
    """How many of `chain`'s part's vertices a regrown chain would weigh most: reweight lays it
    what the chains it hangs from leave of each vertex."""
    body = {name for other in chain.ancestors() for name in other.bones}
    return sum(1 for index in chain.part.vertices
               if sum(weight for name, weight in _named(skin, index).items() if name in body) < 0.5)


def _sibling_count(chain, every, plans):
    """How many bones `chain` is regrown with: as many as most of its siblings have, a sibling
    planned already counting as it will be regrown, as when each was regrown in turn."""
    siblings = [len(plans[other][0]) if other in plans else len(other.bones)
                for other in children(chain.parent, every) if other is not chain]
    return Counter(siblings).most_common(1)[0][0] if siblings else len(chain.bones)


def names(every, leaves, skin):
    """{old bone name: new name} for every bone, by what its chain moves; and each part's chain's
    label for the report. The trunk (the chain at the root) is `hips` and `spine_NN`; a part
    standing on the ground is a leg, any other a stalk, named by its side and its place front to
    back among those on its side."""
    points = [vertex.co for vertex in skin.data.vertices]
    floor = min(point.z for point in points)
    height = max(point.z for point in points) - floor
    half = max(abs(point.x) for point in points)
    groups = {}
    for chain in leaves:
        if chain.part is None:
            continue
        middle = _middle(skin, chain.part.vertices)
        lowest = min(skin.data.vertices[index].co.z for index in chain.part.vertices)
        kind = "leg" if lowest - floor <= GROUND * height else "stalk"
        side = "" if abs(middle.x) <= MIDLINE * half else ".L" if middle.x > 0.0 else ".R"
        groups.setdefault((kind, side), []).append((middle.y, chain.name, chain))
    out, labels = {}, {}
    for (kind, side), members in groups.items():
        members.sort(key=lambda member: member[:2])
        for place, (_y, _name, chain) in enumerate(members):
            pair = PAIRS[len(members)][place] + "_" if len(members) in PAIRS else (
                "" if len(members) == 1 else "%d_" % (place + 1))
            labels[chain.name] = pair + kind + side
            if kind == "leg" and len(chain.bones) == len(LEG_PARTS):
                bones = [pair + part + side for part in LEG_PARTS]
            else:
                bones = ["%s%s_%02d%s" % (pair, kind, number + 1, side) for number in range(len(chain.bones))]
                if kind == "leg" and len(bones) > len(LEG_PARTS):
                    # Its last bone is its paw, named as every leg's, which the clips plant. A
                    # leg of two bones or one has too few above a paw to bend (adopted.limbs).
                    bones[-1] = pair + LEG_PARTS[-1] + side
            out.update(zip(chain.bones, bones))
    for number, chain in enumerate(chain for chain in every if chain not in leaves or chain.part is None):
        if chain.parent is None and number == 0:
            out.update(zip(chain.bones, ["hips"] + ["spine_%02d" % index for index in range(1, len(chain.bones))]))
            labels[chain.name] = "trunk"
        else:
            # A chain between two forks, or a limb with no part of its own: named, never guessed at.
            out.update((name, "chain%d_%02d" % (number, index + 1)) for index, name in enumerate(chain.bones))
            labels[chain.name] = "chain%d" % number
    return out, labels


def rename(rig, skin, renamed):
    """Renames the bones and the skin's vertex groups with them, in two passes so no new name
    collides with an old one. Blender renames the groups of a mesh bound to the rig itself; the
    groups are renamed here too, so the skin never keeps a name its bone has lost."""
    for old in renamed:
        rig.data.bones[old].name = "_" + old
        group = skin.vertex_groups.get(old)
        if group is not None:
            group.name = "_" + old
    for old, new in renamed.items():
        rig.data.bones["_" + old].name = new
        group = skin.vertex_groups.get("_" + old)
        if group is not None:
            group.name = new


def roll(rig):
    """Rolls every bone as quadruped.build does, its local X axis world X, so turning about X bends
    it; a bone lying along X takes world Y instead."""
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in rig.data.edit_bones:
        direction = (bone.tail - bone.head).normalized()
        across = Vector((1.0, 0.0, 0.0)) if abs(direction.x) < 0.7 else Vector((0.0, 1.0, 0.0))
        bone.align_roll(across.cross(direction))
    bpy.ops.object.mode_set(mode="OBJECT")


def flatten(rig, skin):
    """Bakes the rig's and the skin's object transforms into their data, so rig space is world
    space."""
    for obj in (rig, skin):
        matrix = obj.matrix_world.copy()
        obj.parent = None
        if obj is skin:
            obj.data.transform(matrix, shape_keys=True)
        else:
            obj.data.transform(matrix)
        obj.matrix_world = Matrix.Identity(4)
    skin.parent = rig


def place(rig, skin, legs, scale):
    """Moves the model so its feet stand on the ground with the origin between them (the middle
    of every leg's lowest point, or of the whole mesh without legs), sized by `scale` (a number,
    or a function of the placed skin returning one, as import_source.py fits it to its hex), and
    hangs the rig from a new root there. Returns the shift and the scale."""
    points = [vertex.co for vertex in skin.data.vertices]
    feet = [min((skin.data.vertices[index].co for index in chain.part.vertices), key=lambda point: point.z)
            for chain in legs]
    feet = feet or points
    shift = Vector((-sum(point.x for point in feet) / len(feet), -sum(point.y for point in feet) / len(feet),
                    -min(point.z for point in points)))
    skin.data.transform(Matrix.Translation(shift), shape_keys=True)
    rig.data.transform(Matrix.Translation(shift))
    scale = scale(skin) if callable(scale) else scale
    skin.data.transform(Matrix.Scale(scale, 4), shape_keys=True)
    rig.data.transform(Matrix.Scale(scale, 4))
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    tops = [bone for bone in rig.data.edit_bones if bone.parent is None]
    root = rig.data.edit_bones.new("root")
    root.head, root.tail = (0.0, 0.0, 0.0), (0.0, 0.0, ROOT_LENGTH * scale)
    root.use_deform = False
    for bone in tops:
        bone.parent = root
    bpy.ops.object.mode_set(mode="OBJECT")
    return shift, scale


def adopt(rig, skin, scale=1.0):
    """Fixes, names and places the rig `skin` is bound to, printing a line for each thing it
    kept, fixed or renamed. `scale` sizes the model (1: as the download is), or is a function of
    the skin placed on its feet that returns the scale."""
    flatten(rig, skin)
    bones = rig.data.bones
    every = chains(rig)
    leaves = [chain for chain in every if not children(chain, every)]
    balls = forks(every, bones)
    # A rig without a fork (one chain) has no parts to tell apart: it is only named and placed.
    found = split(parts(skin, balls), leaves, skin, bones, balls) if balls else []
    match(leaves, found, skin, bones)
    print("RIG %d bones in %d chains; %d parts outside the forks" % (len(bones), len(every), len(found)))
    twin = twins(leaves, skin, bones)
    for chain, other in twin.items():
        if chain.part is not None and other.part is None:
            # Its twin found no part of its own, so this one's is theirs together (a head piece
            # holding both ears): neither is fixed on it, and it keeps its weights.
            print("TWINS %s and %s: only %s has a part of the mesh; both kept as they are"
                  % (chain.name, other.name, chain.name))
            chain.part.chain, chain.part = None, None
    for part in found:
        if part.chain is None:
            print("ORPHAN a part of %d vertices with no chain of its own: rig it by hand" % len(part.vertices))
    fixes, folded = [], set()
    # Every loose end goes first, so a short chain is regrown with as many bones as its siblings
    # keep.
    loose = {}
    for chain in leaves:
        if chain.part is None:
            loose[chain] = None
        elif turned_back(chain, bones):
            loose[chain] = ("turned", turned_back(chain, bones))
        elif len(chain.bones) > 2 and empty_end(chain, skin):
            loose[chain] = ("empty", 1)
        else:
            loose[chain] = None
    for chain, other in twin.items():
        if loose[chain] != loose[other] and chain.name < other.name:
            print("TWINS %s and %s: their ends differ; neither is folded" % (chain.name, other.name))
            loose[chain] = loose[other] = None
    for chain in leaves:
        if loose[chain] is None:
            continue
        kind, count = loose[chain]
        if kind == "turned":
            fold(rig, skin, chain, count)
            folded.add(chain.name)
            fixes.append("FOLDED %s: its last %d bones turned back on it; their weights went to %s"
                         % (chain.name, count, chain.bones[-1]))
        else:
            # Its last bone moves almost none of its part (a leg's toe bone reaching below the
            # sole, #1619): the bone before it holds the end, so it becomes the paw the clips plant
            # and whose part the ground checks leave to the legs.
            fold(rig, skin, chain, 1)
            folded.add(chain.name)
            fixes.append("FOLDED %s: its last bone moved almost none of its part; its weights went to %s"
                         % (chain.name, chain.bones[-1]))
    # Every regrowth is planned before any is made, so a twin's is measured against the other's.
    plans = {}
    for chain in leaves:
        if chain.part is None:
            continue
        short, reached, whole = is_short(chain, skin, bones)
        if not short:
            continue
        count = _sibling_count(chain, every, plans)
        if _held(skin, chain) < EMPTY_END * len(chain.part.vertices):
            print("WEIGHTLESS %s: short (reaching %.2f of its part's %.2f), but its part moves with the body, "
                  "so regrown bones would weigh almost none of it; kept as it is: rig it by hand"
                  % (chain.name, reached, whole))
            continue
        plans[chain] = (regrown_joints(skin, chain, count), reached, whole)
    starts = {chain: bones[chain.bones[0]].head_local.copy() for chain in leaves}
    # A refused twin keeps its bones, so the plans left are counted again, and a new count moves a
    # plan's tip, so the twins are checked again: until nothing changes (plans only drop or settle).
    for _round in range(len(leaves) + 1):
        ends = {chain: plans[chain][0] if chain in plans else _joints(chain, bones) for chain in leaves}
        refused = set()
        for chain in plans:
            other = twin.get(chain)
            if other is None or other in refused:
                continue
            turn = _direction(starts[chain], ends[chain]).angle(_mirrored(_direction(starts[other], ends[other])), 0.0)
            if turn > TWIN_TURN or (other.part is not None and is_short(other, skin, bones)[0] and other not in plans):
                print("TWINS %s would be regrown %.0f degrees off its twin %s's way, or its twin isn't; "
                      "neither is regrown" % (chain.name, math.degrees(turn), other.name))
                refused.update((chain, other))
        for chain in refused:
            plans.pop(chain, None)
        recounted = False
        for chain in list(plans):
            count = _sibling_count(chain, every, plans)
            if count != len(plans[chain][0]):
                plans[chain] = (regrown_joints(skin, chain, count),) + plans[chain][1:]
                recounted = True
        if not refused and not recounted:
            break
    for chain in leaves:
        if chain.part is None:
            print("UNMATCHED %s: no part of the mesh of its own; kept as it is" % chain.name)
            continue
        old, old_bones = chain.name, list(chain.bones)
        short = chain in plans
        if short:
            joints, reached, whole = plans[chain]
            regrow(rig, skin, chain, joints)
            fixes.append("REGROWN %s: %d bones reaching %.2f of its part's %.2f from the fork; now %d bones"
                         % (old, len(old_bones), reached, whole, len(joints)))
        bled = bleeds(skin, chain, leaves)
        if short or bled:
            reweight(skin, chain, rig.data.bones, short)
        chain.name = "%s..%s" % (chain.bones[0], chain.bones[-1])
        for other, count in sorted(bled.items()):
            fixes.append("BLED %s held weights above %.1f on %d vertices of %s's part: removed"
                         % (other, BLEED, count, old))
        if not short and not bled and old not in folded:
            print("KEEP %s: %d bones, a part of %d vertices" % (old, len(chain.bones), len(chain.part.vertices)))
    for line in fixes:
        print("FIX " + line)
    renamed, labels = names(every, leaves, skin)
    for chain in every:
        first, last = renamed[chain.bones[0]], renamed[chain.bones[-1]]
        span = first if first == last else first + ".." + last
        print("RENAME %s (%s) -> %s" % (chain.name, labels[chain.name], span))
    rename(rig, skin, renamed)
    roll(rig)
    legs = [chain for chain in leaves if chain.part is not None and labels[chain.name].split(".")[0].endswith("leg")]
    shift, scale = place(rig, skin, legs, scale)
    print("PLACE moved by (%.3f, %.3f, %.3f), scaled by %g; a non-deforming root at the origin"
          % (*shift, scale))
    scene.select_only(skin)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
