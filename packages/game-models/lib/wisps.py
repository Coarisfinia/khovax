"""Wisps (#1103): small glowing pieces hovering around a body on their own, each on a bone of its
own that moves nothing but its wisp. The bones hang from the rig's root, not from the body, and a
`loc.<bone>` channel holds each where the clip puts it in the model, whatever the root does
(clips._key), so the body's moves never carry them. `drift` gives them a slow hover on every frame
of every clip, each wisp's wave a little later than the one ahead of it, so the hover flows along
the body. `Gather` makes them shoot to a ring around the head during one clip (an attack) and drift
back, or hold it across clips played in turn (a long attack). Weight each wisp to its bone (parts.part's `bone`) and keep the bones out of the body's
automatic weights (weights.bind's `rigid_bones`)."""

import math

import bpy
from mathutils import Vector

from . import legs, motion, scene

PREFIX = "wisp."
# The channel that places a bone in the model (clips._key).
LOC = "loc."
# How long each wisp's bone is: only its head matters, but a bone needs a length.
LENGTH = 0.05
# How far a wisp bobs up and down and sways sideways (metres, unscaled), how long one wave takes
# at most (seconds), and how fast a wisp may hover (metres a second, unscaled): a clip holds a
# whole number of waves, so they meet at a loop's seam, and a short clip's quicker waves are
# smaller, so a wisp never flies off like a spark.
BOB = 0.03
SWAY = 0.015
PERIOD = 2.0
TOP_SPEED = 0.09
# How far the frontmost wisp's wave runs ahead of the rearmost one's, as a share of a wave.
FLOW = 0.5
# How many frames a ring that rides with a bone takes to settle onto the bone's point where its
# clip meets another clip's ring, so the two meet without a jump.
SETTLE = 6


class Gather:
    """In `clip`, the wisps leave their spots at `start` (frame), the frontmost first and each one
    behind it up to `stagger` frames later, and arrive by `arrive` on a level ring of `radius`
    around `center` (metres, unscaled, the rig's axes), which turns `spin` radians a frame from
    `turn` at `start`; they leave it at `leave` and are back hovering at their spots by `end`.
    A clip that plays on from another one's ring (a long attack's loop and its release, #1158)
    starts on it (`arrive` None), and one that hands on to another one's ring stays on it
    (`leave` None); the ring turns on from where the clip before left it (`turn`). With `bone`
    (the head), the ring rides with that bone, `center` being where it sits at rest: it trails the
    bone's moves through a spring (`lag`: frequency in Hz and damping, motion.spring), so it sways
    with the head, softly, rather than hanging fixed or stuck to it. Where a clip meets another
    one's ring, the ring has settled onto the bone's point (SETTLE), so the clips meet there."""

    def __init__(self, clip, start, arrive, leave, end, center, radius, spin=0.0, stagger=0, turn=0.0, bone=None,
                 lag=(2.5, 0.5)):
        self.clip, self.start, self.arrive, self.leave, self.end = clip, start, arrive, leave, end
        self.center, self.radius, self.spin, self.stagger = Vector(center), radius, spin, stagger
        self.turn, self.bone, self.lag = turn, bone, lag

    def share(self, frame, late):
        """How far (0..1) a wisp `late` frames behind the first is from its spot to the ring."""
        if self.leave is not None and frame > self.leave:
            return 1.0 - legs.ease((frame - self.leave) / (self.end - self.leave))
        if self.arrive is None:
            return 1.0
        return legs.ease((frame - self.start - late) / (self.arrive - self.start - late))

    def centers(self, shape, poses, loop):
        """The ring's centre on every frame of `poses` (unscaled metres): fixed, or trailing its
        bone's moves on `shape` (motion.Rig of the unscaled rig)."""
        if self.bone is None:
            return [self.center for _pose in poses]
        rest = shape.matrix[self.bone].inverted()
        moved = [legs.posed(shape, pose, self.bone, 1.0, {}) @ rest @ self.center for _frame, pose in poses]
        lagged = motion.spring(moved, *self.lag, 0.0, bpy.context.scene.render.fps, loop)
        first, last = poses[0][0], poses[-1][0]
        out = []
        for (frame, _pose), target, trailing in zip(poses, moved, lagged):
            # Settled onto the bone's point where the ring meets another clip's: a start that
            # plays on from one, an end that hands on to one, and both sides of a loop's seam.
            hold = 1.0
            if self.arrive is None:
                hold = min(hold, legs.ease((frame - first) / SETTLE))
            if self.leave is None:
                hold = min(hold, legs.ease((last - frame) / SETTLE))
            out.append(target + (trailing - target) * hold)
        return out

    def spot(self, index, count, frame, center):
        angle = 2.0 * math.pi * index / count + self.turn + self.spin * (frame - self.start)
        return center + Vector((math.sin(angle), -math.cos(angle), 0.0)) * self.radius


class Wisps:
    """The wisps' bones on `rig`, at `spots` (where each wisp hovers, in the rig's unscaled metres,
    before scene.apply_scale), named `wisp.0`, `wisp.1`, ... in that order (`names`), and the
    clips they gather in (`gathers`, Gathers)."""

    def __init__(self, rig, spots, gathers=()):
        self.names = [PREFIX + str(index) for index in range(len(spots))]
        self.spots = [Vector(spot) for spot in spots]
        self.gathers = {gather.clip: gather for gather in gathers}
        scene.select_only(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        root = next(bone for bone in rig.data.edit_bones if bone.parent is None)
        for name, spot in zip(self.names, self.spots):
            bone = rig.data.edit_bones.new(name)
            bone.head = spot
            bone.tail = spot + Vector((0.0, 0.0, LENGTH))
            # The root's axes (sideways, up, forward), as the root's own shift.
            bone.align_roll(Vector((1.0, 0.0, 0.0)).cross(bone.tail - bone.head))
            bone.parent = root
        bpy.ops.object.mode_set(mode="OBJECT")
        # The rig as built, in unscaled metres like the clips' root_loc, for a ring that rides
        # with a bone.
        self.shape = motion.Rig(rig)
        ahead = [spot.y for spot in self.spots]
        span = max(max(ahead) - min(ahead), 1e-6)
        # The share of the way from the frontmost wisp to the rearmost, which sets each one's
        # phase and how late it gathers.
        self.rank = [(y - min(ahead)) / span for y in ahead]

    def drift(self, name, poses, loop):
        """Places every wisp on every frame of `poses` ([(frame, pose)], every frame, as motion.fill
        gives them): a hover starting and ending at its spot, so a loop meets itself and a one-shot
        clip hands on to the next there, and the ring if the clip gathers them."""
        span = poses[-1][0] - poses[0][0]
        seconds = span / bpy.context.scene.render.fps
        waves = max(1, round(seconds / PERIOD))
        swing = 2.0 * math.pi * waves / seconds * math.hypot(BOB, SWAY)
        share = min(1.0, TOP_SPEED / swing)
        gather = self.gathers.get(name)
        centers = gather.centers(self.shape, poses, loop) if gather is not None else [None] * len(poses)
        for (frame, pose), center in zip(poses, centers):
            t = 2.0 * math.pi * waves * (frame - poses[0][0]) / span
            for index, (bone, rank) in enumerate(zip(self.names, self.rank)):
                phase = -2.0 * math.pi * FLOW * rank
                # (sideways, up, forward) from its spot; the rig faces -Y.
                hover = Vector((share * SWAY * (math.cos(t + phase) - math.cos(phase)),
                                share * BOB * (math.sin(t + phase) - math.sin(phase)), 0.0))
                if gather is not None:
                    ring = gather.spot(index, len(self.names), frame, center) - self.spots[index]
                    toward = Vector((ring.x, ring.z, -ring.y)) - hover
                    hover = hover + toward * gather.share(frame, round(gather.stagger * rank))
                pose[LOC + bone] = tuple(hover)
