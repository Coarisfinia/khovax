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
    - `jaw`: (hinge, chin); `ear`: (base, tip); `scapula`: its top, above the front leg.
    - `front_leg`: shoulder, elbow, wrist, paw tip; `hind_leg`: hip, knee, hock, ankle, paw tip.
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


def _chain(out, names, points, parent, side):
    for index, name in enumerate(names):
        out.append((name + "." + side, points[index], points[index + 1], parent))
        parent = name + "." + side
