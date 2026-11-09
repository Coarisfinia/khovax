"""Attachment points (#1007): named spots on a model that follow its rig through every clip, for
effects the game places there later. Every model has one per eye (`eye.L`, `eye.R`, or any
`eye.<name>`; none is fine for a model without eyes) and at least one centre of attack, one per
thing it attacks with (`attack.0`, `attack.1`, ...: a mouth, each striking arm). Each is a small
bone that deforms nothing, its head at the spot and parented to the bone it moves with (a head,
a jaw, an arm), so the glTF export carries it as a joint and the game reads it as a skeleton bone
(`ModelPoints` in the game). An eye's bone points the way the eye looks, so the game can tell how
far it faces the camera (`EyeGlow`); every other point's bone points up."""

import bpy
from mathutils import Vector

from . import scene

EYE = "eye."
ATTACK = "attack."
# How long each point's bone is: only its head matters, but a bone needs a length.
LENGTH = 0.02


def add(rig, eyes, attacks):
    """Adds the points to `rig`, in the rig's unscaled metres (before scene.apply_scale).
    `eyes` maps each eye's side or name ("L", "R") to (spot, bone, look), its bone pointing from
    its spot the way it looks (`eyes.look`), and `attacks` is a list of (spot, bone), numbered in
    order, each bone pointing up from its spot."""
    if not attacks:
        raise ValueError("a model needs at least one centre of attack")
    up = (0.0, 0.0, 1.0)
    points = [(EYE + name, spot, bone, look) for name, (spot, bone, look) in eyes.items()]
    points += [(ATTACK + str(index), spot, bone, up) for index, (spot, bone) in enumerate(attacks)]
    scene.select_only(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, spot, parent, direction in points:
        bone = rig.data.edit_bones.new(name)
        bone.head = Vector(spot)
        bone.tail = Vector(spot) + Vector(direction).normalized() * LENGTH
        bone.parent = rig.data.edit_bones[parent]
        bone.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
