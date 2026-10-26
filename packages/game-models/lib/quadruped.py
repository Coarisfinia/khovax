"""A quadruped's armature from its proportions: root, hips, a two-bone spine, neck, head, jaw,
ears, a tail chain and four legs of four bones each, named .L/.R. Every bone lies in its
side's YZ plane, rolled so its local X axis is world X: rotating about X bends it the way a
spine and legs bend, about Z sways it. Blender is Z-up and the animal faces -Y, which the glTF
export turns into the game's Y-up, facing +Z."""

import bpy
from mathutils import Vector

from . import scene


def mirrored(point):
    return (-point[0], point[1], point[2])


class Proportions:
    """Where a quadruped's joints are, in metres, for its left side (the right mirrors across X).

    - `tail`: tip first; its first bone runs from the hips to its last point.
    - `hips`, `waist` (where the spine bends), `chest`, `head_base`, `nose`.
    - `jaw`: (joint, chin), the joint where the skull hinges it; `ear`: (base, tip); `scapula`: its top, above the front leg.
    - `front_leg`: shoulder, elbow, wrist, paw tip; `hind_leg`: hip, knee, hock, ankle, paw tip.
    - `tongue` (optional): (root, tip), lying on the mouth's floor, on a bone of its own hung from
      the jaw, so a clip can loll it out (muzzle.Snout.tongue).
    """

    def __init__(self, **joints):
        for name, value in joints.items():
            setattr(self, name, value)


def bones(p):
    """(name, head, tail, parent) for every bone."""
    out = [
        ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.3), None),
        ("hips", p.hips, p.waist, "root"),
        ("spine_01", p.waist, _between(p.waist, p.chest), "hips"),
        ("spine_02", _between(p.waist, p.chest), p.chest, "spine_01"),
        ("neck", p.chest, p.head_base, "spine_02"),
        ("head", p.head_base, p.nose, "neck"),
        ("jaw", p.jaw[0], p.jaw[1], "head"),
    ]
    if getattr(p, "tongue", None) is not None:
        out.append(("tongue", p.tongue[0], p.tongue[1], "jaw"))
    parent, previous = "hips", p.hips
    for index, point in enumerate(reversed(p.tail)):
        name = "tail_%02d" % (index + 1)
        out.append((name, previous, point, parent))
        parent, previous = name, point
    for side, flip in (("L", lambda q: q), ("R", mirrored)):
        out.append(("ear." + side, flip(p.ear[0]), flip(p.ear[1]), "head"))
        front = [flip(q) for q in p.front_leg]
        out.append(("scapula." + side, flip(p.scapula), front[0], "spine_02"))
        _chain(out, ["upper_arm", "forearm", "front_paw"], front, "scapula." + side, side)
        _chain(out, ["thigh", "shin", "hock", "hind_paw"], [flip(q) for q in p.hind_leg], "hips", side)
    return out


def armature(name, proportions):
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(rig)
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent in bones(proportions):
        bone = data.edit_bones.new(bone_name)
        bone.head, bone.tail = head, tail
        direction = (Vector(tail) - Vector(head)).normalized()
        bone.align_roll(Vector((1.0, 0.0, 0.0)).cross(direction))
        if parent is not None:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = (Vector(bone.parent.tail) - Vector(head)).length < 1e-4
        bone.use_deform = bone_name != "root"
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _between(a, b):
    return tuple((x + y) / 2 for x, y in zip(a, b))


def _trunk(skin, rig, names, middle=False):
    """The trunk bones `names`, each with where it lies along the body (y: its rest head, or with
    `middle` its middle) and its vertex group, in order along the body."""
    trunk = []
    for name in names:
        group = skin.vertex_groups.get(name) or skin.vertex_groups.new(name=name)
        bone = rig.data.bones[name]
        trunk.append(((bone.head_local.y + bone.tail_local.y) / 2.0 if middle else bone.head_local.y, group))
    trunk.sort(key=lambda item: item[0])
    return trunk


def _hand_to_trunk(trunk, index, point, taken):
    """Gives the vertex `index` at `point` (rig space) a `taken` weight on the trunk bones, blended
    between the two whose heads lie either side of it along the body."""
    for (start, first), (end, second) in zip(trunk, trunk[1:]):
        if point.y <= end:
            along = max(0.0, min(1.0, (point.y - start) / (end - start)))
            first.add([index], taken * (1.0 - along), "ADD")
            second.add([index], taken * along, "ADD")
            return
    trunk[-1][1].add([index], taken, "ADD")


def _limbs(rig, roots):
    """The bones of the limbs whose roots are `roots` (each root and every bone below it)."""
    return {bone.name for name in roots for bone in [rig.data.bones[name], *rig.data.bones[name].children_recursive]}


def _smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def bind_torso(skin, rig, bottom, top):
    """Keeps the upper trunk with its spine rather than the legs' automatic weights. Between
    `bottom` and `top` (rest height in rig space), smoothly transfers the legs' influence to
    the hips and spine, blended along their length. Below it the legs keep their weights;
    head, jaw and tail weights are untouched. Runs before pieces join the skin (weights.bind's
    `reweigh`), so markings on the torso inherit its corrected weights too."""
    limbs = _limbs(rig, [name + "." + side for name in ("scapula", "thigh") for side in ("L", "R")])
    sources = {group.index for group in skin.vertex_groups if group.name in limbs}
    spine = _trunk(skin, rig, ("hips", "spine_01", "spine_02"))
    to_rig = rig.matrix_world.inverted() @ skin.matrix_world
    for vertex in skin.data.vertices:
        point = to_rig @ vertex.co
        share = _smooth((point.z - bottom) / (top - bottom))
        if share == 0.0:
            continue
        taken = 0.0
        for index, weight in [(group.group, group.weight) for group in vertex.groups if group.group in sources]:
            moved = weight * share
            skin.vertex_groups[index].add([vertex.index], weight - moved, "REPLACE")
            taken += moved
        if taken > 0.0:
            _hand_to_trunk(spine, vertex.index, point, taken)


# Between the legs (#1422), as shares of how far out a leg stands from the midline: the skin
# nearer the midline than INNER is wholly the trunk's, beyond OUTER wholly the leg's, eased between.
INNER, OUTER = 0.4, 0.8


def bind_underside(skin, rig, inner=INNER, outer=OUTER):
    """Keeps the skin between the legs with the trunk (#1422): the chest's and throat's underside
    between the forelegs, the belly between the hind legs and the back between the shoulder
    blades. Automatic weights give that skin to the nearest leg bones, so it rose with a foreleg
    swinging back or folding (a walk, a crouch, a faint) and the body thinned out over it (the
    owner, on #1305). Near the midline (`inner` and `outer`, shares of how far out the leg's root
    stands) and above the elbows and knees, the legs' share goes to the spine and neck, blended
    along the body; not to the head, whose skin is the head's measure in `metrics`. The legs keep
    the skin at their own sides. Runs as `bind_torso` does, before pieces join the skin."""
    legs = {}
    for root, top, joint in (("scapula", "upper_arm", "forearm"), ("thigh", "thigh", "shin")):
        for side in ("L", "R"):
            head = rig.data.bones[top + "." + side].head_local
            low = rig.data.bones[joint + "." + side].head_local.z
            # (how far out the leg stands, the elbow's or knee's height, and halfway up to the
            # leg's root): the leg's own skin, below, keeps all of its weights.
            leg = (abs(head.x), low, (low + head.z) / 2.0)
            for name in _limbs(rig, [root + "." + side]):
                group = skin.vertex_groups.get(name)
                if group is not None:
                    legs[group.index] = leg
    # Each bone takes the skin around its middle, and two share it where they meet: skin just
    # behind the neck's root (the crest's first crystal) stays the chest's as the neck bows.
    trunk = _trunk(skin, rig, ("hips", "spine_01", "spine_02", "neck"), middle=True)
    to_rig = rig.matrix_world.inverted() @ skin.matrix_world
    for vertex in skin.data.vertices:
        point = to_rig @ vertex.co
        taken = 0.0
        for index, weight in [(group.group, group.weight) for group in vertex.groups if group.group in legs]:
            reach, low, high = legs[index]
            across = 1.0 - _smooth((abs(point.x) / reach - inner) / (outer - inner))
            moved = weight * across * _smooth((point.z - low) / (high - low))
            if moved > 0.0:
                skin.vertex_groups[index].add([vertex.index], weight - moved, "REPLACE")
                taken += moved
        if taken > 0.0:
            _hand_to_trunk(trunk, vertex.index, point, taken)


def _chain(out, names, points, parent, side):
    for index, name in enumerate(names):
        out.append((name + "." + side, points[index], points[index + 1], parent))
        parent = name + "." + side
