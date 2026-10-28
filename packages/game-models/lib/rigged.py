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

Vertices inside a fork's ball keep their weights: that's where the parts blend into the body.
Then every bone is named to the library's scheme by what its chain moves (`<pair>_leg_NN.<side>`,
`<pair>_thigh.L` for a three-bone leg as the hexapod has, `hips` and `spine_NN` for the trunk),
rolled as the library's armatures are (quadruped.build), and hung from a new `root` on the ground
between the feet, which the clips move. It prints what it kept, fixed and renamed.

Blender is Z-up and the model faces -Y; a part's left is +X."""

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
        centre = bones[chain.bones[-1]].tail_local
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


def regrow(rig, skin, chain, count):
    """Replaces `chain`'s bones with `count` bones through its part's middle: the first from where
    the chain starts, each next one ending at the middle of the next band of the part (by
    distance from its fork), the last at its far end. Weights the old bones held outside the
    part, inside the fork's ball, go to the bone the chain hangs from: there the body is moved,
    not the part. Returns the new bones' names."""
    part = chain.part
    centre = part.fork[0]
    far = {index: (skin.data.vertices[index].co - centre).length for index in part.vertices}
    low, high = min(far.values()), max(far.values())
    width = (high - low) / count
    joints = []
    for band in range(count - 1):
        inside = [index for index, distance in far.items() if low + band * width <= distance < low + (band + 1) * width]
        joints.append(_middle(skin, inside))
    joints.append(_middle(skin, [index for index, distance in far.items() if distance >= high - width / 4]))
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


def rename(rig, renamed):
    """Renames the bones, and with them the skin's vertex groups (Blender renames those with
    their bones), in two passes so no new name collides with an old one."""
    for old in renamed:
        rig.data.bones[old].name = "_" + old
    for old, new in renamed.items():
        rig.data.bones["_" + old].name = new


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
        obj.data.transform(matrix)
        obj.matrix_world = Matrix.Identity(4)
    skin.parent = rig


def place(rig, skin, legs, scale):
    """Moves the model so its feet stand on the ground with the origin between them (the middle
    of every leg's lowest point, or of the whole mesh without legs), sized by `scale`, and hangs
    the rig from a new root there. Returns the shift."""
    points = [vertex.co for vertex in skin.data.vertices]
    feet = [min((skin.data.vertices[index].co for index in chain.part.vertices), key=lambda point: point.z)
            for chain in legs]
    feet = feet or points
    shift = Vector((-sum(point.x for point in feet) / len(feet), -sum(point.y for point in feet) / len(feet),
                    -min(point.z for point in points)))
    matrix = Matrix.Scale(scale, 4) @ Matrix.Translation(shift)
    skin.data.transform(matrix)
    rig.data.transform(matrix)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    tops = [bone for bone in rig.data.edit_bones if bone.parent is None]
    root = rig.data.edit_bones.new("root")
    root.head, root.tail = (0.0, 0.0, 0.0), (0.0, 0.0, ROOT_LENGTH * scale)
    root.use_deform = False
    for bone in tops:
        bone.parent = root
    bpy.ops.object.mode_set(mode="OBJECT")
    return shift


def adopt(rig, skin, scale=1.0):
    """Fixes, names and places the rig `skin` is bound to, printing a line for each thing it
    kept, fixed or renamed. `scale` sizes the model (1: as the download is)."""
    flatten(rig, skin)
    bones = rig.data.bones
    every = chains(rig)
    leaves = [chain for chain in every if not children(chain, every)]
    found = parts(skin, forks(every, bones))
    match(leaves, found, skin, bones)
    print("RIG %d bones in %d chains; %d parts outside the forks" % (len(bones), len(every), len(found)))
    for part in found:
        if part.chain is None:
            print("ORPHAN a part of %d vertices with no chain of its own: rig it by hand" % len(part.vertices))
    fixes = []
    for chain in leaves:
        if chain.part is None:
            print("UNMATCHED %s: no part of the mesh of its own; kept as it is" % chain.name)
            continue
        short, joints, whole = is_short(chain, skin, bones)
        old, old_bones = chain.name, list(chain.bones)
        if short:
            siblings = [len(other.bones) for other in children(chain.parent, every) if other is not chain]
            count = Counter(siblings).most_common(1)[0][0] if siblings else len(chain.bones)
            regrow(rig, skin, chain, count)
            fixes.append("REGROWN %s: %d bones reaching %.2f of its part's %.2f from the fork; now %d bones"
                         % (old, len(old_bones), joints, whole, count))
        bled = bleeds(skin, chain, leaves)
        if short or bled:
            reweight(skin, chain, rig.data.bones, short)
        chain.name = "%s..%s" % (chain.bones[0], chain.bones[-1])
        for other, count in sorted(bled.items()):
            fixes.append("BLED %s held weights above %.1f on %d vertices of %s's part: removed"
                         % (other, BLEED, count, old))
        if not short and not bled:
            print("KEEP %s: %d bones, a part of %d vertices" % (old, len(chain.bones), len(chain.part.vertices)))
    for line in fixes:
        print("FIX " + line)
    renamed, labels = names(every, leaves, skin)
    for chain in every:
        first, last = renamed[chain.bones[0]], renamed[chain.bones[-1]]
        span = first if first == last else first + ".." + last
        print("RENAME %s (%s) -> %s" % (chain.name, labels[chain.name], span))
    rename(rig, renamed)
    roll(rig)
    legs = [chain for chain in leaves if chain.part is not None and labels[chain.name].split(".")[0].endswith("leg")]
    shift = place(rig, skin, legs, scale)
    print("PLACE moved by (%.3f, %.3f, %.3f), scaled by %g; a non-deforming root at the origin"
          % (*shift, scale))
    scene.select_only(skin)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
