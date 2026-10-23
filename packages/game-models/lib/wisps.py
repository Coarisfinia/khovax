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
from mathutils import Matrix, Vector

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
# How many frames a ring that rides with a bone takes to settle upright where its clip meets
# another clip's ring, so the two meet without a jump.
SETTLE = 6
# With a Gather's `rise`: the share of a flight a wisp spends climbing to its flight height (and
# as much coming down from it), and the share at each end where it only climbs or comes down, so
# it neither leaves its spot nor reaches the ring sideways through what stands beside them (an ear
# beside the ring).
CLIMB = 0.35
STRAIGHT_UP = 0.2
# How far out from the ring's centre, against its up, a wisp comes down onto it: from above and a
# little outside, so it clears an ear standing up inside the ring.
OUTWARD = 0.5


class Gather:
    """In `clip`, the wisps leave their spots at `start` (frame), the frontmost first and each one
    behind it up to `stagger` frames later, and arrive by `arrive` on a level ring of `radius`
    around `center` (metres, unscaled, the rig's axes), which turns `spin` radians a frame from
    `turn` at `start`; they leave it at `leave` and are back hovering at their spots by `end`.
    A clip that plays on from another one's ring (a long attack's loop and its release, #1158)
    starts on it (`arrive` None), and one that hands on to another one's ring stays on it
    (`leave` None); the ring turns on from where the clip before left it (`turn`). With `bone`
    (the head), the ring rides with that bone, `center` being where it sits at rest, level: it
    turns and tilts with the bone, so it can hug it, and leans like a loose hoop as the bone moves.
    The lean comes from how far a spring (`lag`: frequency in Hz and damping, motion.spring) would
    trail the bone's point: the side the ring trails toward lifts, up to `lean` (radians, reached
    softly; `lever`, metres, is the trail that leans it about three quarters of the way), and the
    underdamped spring swings it back past upright, so it sways with the head rather than sitting
    stuck to it. Where a clip meets another one's ring the lean has settled (SETTLE), so the clips
    meet there.
    With `rise` (metres), a wisp doesn't fly straight between its spot and the ring, which would
    cut through whatever stands between them (#1182): it climbs to `rise` above the higher of the
    two, flies over at that height and comes down onto the ring from above it and a little outside
    (OUTWARD), in the ring's own frame (which tilts with the head), the climb and the descent each taking CLIMB of the flight (STRAIGHT_UP of
    it straight up or down), and leaves the ring the same way back."""

    def __init__(self, clip, start, arrive, leave, end, center, radius, spin=0.0, stagger=0, turn=0.0, bone=None,
                 lag=(1.5, 0.3), lean=math.radians(12.0), lever=0.02, rise=None):
        self.clip, self.start, self.arrive, self.leave, self.end = clip, start, arrive, leave, end
        self.center, self.radius, self.spin, self.stagger = Vector(center), radius, spin, stagger
        self.turn, self.bone, self.lag, self.lean, self.lever = turn, bone, lag, lean, lever
        self.rise = rise

    def progress(self, frame, late):
        """How far (0..1, not eased) a wisp `late` frames behind the first has flown from its spot
        to the ring."""
        if self.leave is not None and frame > self.leave:
            return 1.0 - min(1.0, max(0.0, (frame - self.leave) / (self.end - self.leave)))
        if self.arrive is None:
            return 1.0
        return min(1.0, max(0.0, (frame - self.start - late) / (self.arrive - self.start - late)))

    def fly(self, spot, ring, toward, s):
        """Where a wisp is `s` (progress) of the way from `spot` to `ring`, all three (sideways,
        up, forward) from its spot, `toward` being the way it comes down onto the ring (from above
        and outside): eased along the straight line, or with a `rise` from its spot raised to the
        flight height to the ring raised to it along `toward`."""
        if self.rise is None:
            return spot + (ring - spot) * legs.ease(s)
        top = max(spot.y, ring.y) + self.rise
        lifted = spot + Vector((0.0, top - spot.y, 0.0)) * legs.ease(s / CLIMB)
        above = ring + toward * ((top - ring.y) / max(toward.y, 0.5)) * legs.ease((1.0 - s) / CLIMB)
        return lifted + (above - lifted) * legs.ease((s - STRAIGHT_UP) / (1.0 - 2.0 * STRAIGHT_UP))

    def rings(self, shape, poses, loop):
        """The ring's centre (unscaled metres) and its turn (a 3x3 Matrix from level) on every
        frame of `poses`: fixed and level, or riding its bone on `shape` (motion.Rig of the
        unscaled rig) and leaning as it moves."""
        if self.bone is None:
            return [(self.center, Matrix.Identity(3)) for _pose in poses]
        rest = shape.matrix[self.bone].inverted()
        carried = [legs.posed(shape, pose, self.bone, 1.0, {}) @ rest for _frame, pose in poses]
        moved = [carry @ self.center for carry in carried]
        lagged = motion.spring(moved, *self.lag, 0.0, bpy.context.scene.render.fps, loop)
        first, last = poses[0][0], poses[-1][0]
        out = []
        for (frame, _pose), carry, target, trailing in zip(poses, carried, moved, lagged):
            # Upright where the ring meets another clip's: a start that plays on from one, an end
            # that hands on to one, and both sides of a loop's seam.
            hold = 1.0
            if self.arrive is None:
                hold = min(hold, legs.ease((frame - first) / SETTLE))
            if self.leave is None:
                hold = min(hold, legs.ease((last - frame) / SETTLE))
            turn = carry.to_3x3().normalized()
            up = turn @ Vector((0.0, 0.0, 1.0))
            trail = (trailing - target) * hold
            trail -= up * trail.dot(up)
            if trail.length > 1e-9:
                tip = self.lean * math.tanh(trail.length / self.lever)
                turn = Matrix.Rotation(tip, 3, trail.cross(up).normalized()) @ turn
            out.append((target, turn))
        return out

    def spot(self, index, count, frame, ring):
        center, turn = ring
        angle = 2.0 * math.pi * index / count + self.turn + self.spin * (frame - self.start)
        return center + turn @ Vector((math.sin(angle), -math.cos(angle), 0.0)) * self.radius


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
        rings = gather.rings(self.shape, poses, loop) if gather is not None else [None] * len(poses)
        for (frame, pose), held in zip(poses, rings):
            t = 2.0 * math.pi * waves * (frame - poses[0][0]) / span
            for index, (bone, rank) in enumerate(zip(self.names, self.rank)):
                phase = -2.0 * math.pi * FLOW * rank
                # (sideways, up, forward) from its spot; the rig faces -Y.
                hover = Vector((share * SWAY * (math.cos(t + phase) - math.cos(phase)),
                                share * BOB * (math.sin(t + phase) - math.sin(phase)), 0.0))
                if gather is not None:
                    ring = gather.spot(index, len(self.names), frame, held)
                    toward = held[1] @ Vector((0.0, 0.0, 1.0)) + (ring - held[0]).normalized() * OUTWARD
                    ring = ring - self.spots[index]
                    hover = gather.fly(hover, Vector((ring.x, ring.z, -ring.y)),
                                       Vector((toward.x, toward.z, -toward.y)),
                                       gather.progress(frame, round(gather.stagger * rank)))
                pose[LOC + bone] = tuple(hover)
