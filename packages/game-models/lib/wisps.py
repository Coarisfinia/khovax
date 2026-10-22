"""Wisps (#1103): small glowing pieces floating beside a body, each on a bone of its own that moves
nothing but its wisp. The bone hangs from the body bone the wisp goes with, its head LEVER ahead
of the wisp (toward the nose) and its tail at the wisp, so a small turn of it moves the wisp a
little: `drift` turns it in a slow bob and sway on every frame of every clip, each wisp's wave a
little later than the one ahead of it, so the drift flows along the body, and `follow` lets each
wisp trail its body bone on a loose spring (motion.follow), so it floats rather than being
carried rigidly. Weight each wisp to its bone (parts.part's `bone`) and keep the bones out of the
body's automatic weights (weights.bind's `rigid_bones`)."""

import math

import bpy
from mathutils import Vector

from . import scene

PREFIX = "wisp."
# How far ahead of its wisp a wisp's bone turns (metres, unscaled).
LEVER = 0.2
# How far a wisp bobs up and down and sways sideways (metres, unscaled), how long one wave takes
# at most (seconds), and how fast a wisp may drift (metres a second, unscaled): a clip holds a
# whole number of waves, so they meet at a loop's seam, and a short clip's quicker waves are
# smaller, so a wisp never flies off like a spark.
BOB = 0.025
SWAY = 0.012
PERIOD = 2.0
TOP_SPEED = 0.09
# How far the frontmost wisp's wave runs ahead of the rearmost one's, as a share of a wave.
FLOW = 0.5
# The wisps' spring (motion.follow's frequency, damping, response and shift): loose, but firm enough
# that a sudden move (a blow, a lunge) never flings them.
SPRING = (2.0, 0.6, 0.0, 0.1)


class Wisps:
    """The wisps' bones on `rig`, from `spots`, [(spot, bone)]: where each wisp is and the body bone
    it goes with, in the rig's unscaled metres (before scene.apply_scale). The bones are named
    `wisp.0`, `wisp.1`, ... in that order (`names`)."""

    def __init__(self, rig, spots):
        self.names = [PREFIX + str(index) for index in range(len(spots))]
        scene.select_only(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        for name, (spot, parent) in zip(self.names, spots):
            bone = rig.data.edit_bones.new(name)
            bone.head = Vector(spot) + Vector((0.0, -LEVER, 0.0))
            bone.tail = Vector(spot)
            # Its X axis is the world's, as the quadruped's bones: about X it bobs, about Z it sways.
            bone.align_roll(Vector((1.0, 0.0, 0.0)).cross(bone.tail - bone.head))
            bone.parent = rig.data.edit_bones[parent]
        bpy.ops.object.mode_set(mode="OBJECT")
        ahead = [spot[1] for spot, _bone in spots]
        span = max(max(ahead) - min(ahead), 1e-6)
        self.phases = [-2.0 * math.pi * FLOW * (y - min(ahead)) / span for y in ahead]

    def follow(self):
        """The wisps' chains for clips.animate's `chains`."""
        return {name: SPRING for name in self.names}

    def drift(self, poses, _loop):
        """Turns every wisp's bone through `poses` ([(frame, pose)], every frame, as motion.fill
        gives them), starting and ending at rest, so a loop meets itself and a one-shot clip hands
        on to the next at rest."""
        span = poses[-1][0] - poses[0][0]
        seconds = span / bpy.context.scene.render.fps
        waves = max(1, round(seconds / PERIOD))
        swing = 2.0 * math.pi * waves / seconds * math.hypot(BOB, SWAY)
        share = min(1.0, TOP_SPEED / swing)
        for frame, pose in poses:
            t = 2.0 * math.pi * waves * (frame - poses[0][0]) / span
            for name, phase in zip(self.names, self.phases):
                bob = math.sin(t + phase) - math.sin(phase)
                sway = math.cos(t + phase) - math.cos(phase)
                pose[name] = (share * BOB * bob / LEVER, 0.0, share * SWAY * sway / LEVER)
