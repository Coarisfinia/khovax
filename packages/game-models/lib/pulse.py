"""Pulses (#1224): a part that swells and settles on a beat, such as a glowing crystal flaring in
step with something else the clip does. The part is weighted to a bone of its own (parts.part's
`bone`, kept out of the body's automatic weights through weights.bind's `rigid_bones`), hung from
the bone it moves with, its head where the part grows from, so scaling the bone swells the part
out from there. `beat`, an animate overlay, keys the bone's scale (a `scale.<bone>` channel,
clips._key) on every frame of every clip: at rest outside the beats, so every other clip sets it
back."""

import math

import bpy
from mathutils import Vector

from . import scene

SCALE = "scale."
# What a pulsing part's bone is named after: metrics counts it as its parent's.
PREFIX = "pulse."
# How long the bone is: only its head matters, but a bone needs a length.
LENGTH = 0.02


class Pulse:
    """A bone `pulse.<part>` on `rig` (`name`), its head at `spot` (the rig's unscaled metres, before
    scene.apply_scale), hung from `parent`. In each clip of `beats` ({clip: [frame, ...]}) the
    part swells to `amount` times its size at each beat's frame, rising over `rise` frames before
    it and settling over `fall` frames after it, both eased. A beat may lie outside its clip's
    frames: the clip then shows the part of the pulse it covers, so a pulse can run on from one
    clip into the next one the game plays after it, and a loop holds the beats on either side of
    its seam."""

    def __init__(self, rig, part, spot, parent, beats, amount=1.3, rise=5, fall=15):
        name = PREFIX + part
        self.name, self.beats, self.amount, self.rise, self.fall = name, beats, amount, rise, fall
        scene.select_only(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        bone = rig.data.edit_bones.new(name)
        bone.head = Vector(spot)
        bone.tail = Vector(spot) + Vector((0.0, 0.0, LENGTH))
        bone.parent = rig.data.edit_bones[parent]
        bpy.ops.object.mode_set(mode="OBJECT")

    def swell(self, distance):
        """How far (0..1) the part has swollen `distance` frames after a beat (before it, if
        less than nothing)."""
        if -self.rise < distance <= 0:
            return 0.5 + 0.5 * math.cos(math.pi * distance / self.rise)
        if 0 < distance < self.fall:
            return 0.5 + 0.5 * math.cos(math.pi * distance / self.fall)
        return 0.0

    def beat(self, name, poses, _loop):
        """Scales the bone on every frame of `poses` ([(frame, pose)], every frame)."""
        beats = self.beats.get(name, ())
        for frame, pose in poses:
            size = 1.0 + (self.amount - 1.0) * min(1.0, sum(self.swell(frame - at) for at in beats))
            pose[SCALE + self.name] = (size, size, size)
