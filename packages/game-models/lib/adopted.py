"""An adopted rig's limbs for the library's clips (#1539): a generated model's rig, as
lib/rigged.py names it, has legs and stalks of many bones, where the library's own rigs have
three bones a leg and a four-bone tail.

- `limbs`: every leg (a chain ending in a `<pair>_paw.<side>`) as a legs.Leg: its bones above
  the joint where the leg bends most as one run, the bones below it down to the paw as another,
  each turning as one, in the plane through its top, that joint and its paw (legs.Leg's
  `plane`), so the clips plant its paw as they plant a quadruped's or a hexapod's.
- `follow`: every stalk (a chain starting at a `<pair>_stalk_01.<side>`) for motion.follow, each
  bone looser than the one before it, as the quadruped's tail is (clips.FOLLOW).
- `Body`: what clips.gait reads of a body, from a rig named to the quadruped's scheme.
- `lesser`: one of the library's clips scaled down for shorter legs (#1609).

Blender is Z-up and the model faces -Y."""

from mathutils.geometry import intersect_point_line

from . import legs

# A stalk's first bone trails its parent as the quadruped's tail's first bone does; each next
# bone is this much quicker to come loose (a lower frequency) and wobbles a little more.
STALK = (2.8, 0.5, 0.0, 0.15)
LOOSER = 0.9
WOBBLIER = 0.05
# The lowest frequency (Hz) and damping a stalk's tip comes to: a looser spring lags a long
# stalk's tip a whole beat behind.
LOOSEST = (1.6, 0.35)
# A leg bent less than this share of its length off the line from its top to its paw is straight:
# it has no plane of its own to bend in.
STRAIGHT = 0.02


def _row(bone):
    """`bone` and the bones hanging from it one after the other, to where the row forks or ends."""
    out = [bone]
    while len(out[-1].children) == 1:
        out.append(out[-1].children[0])
    return out


def _leg(paw):
    """The bones above `paw` up to where its leg hangs from the body (a bone with other children),
    top first."""
    out = [paw]
    while out[-1].parent is not None and len(out[-1].parent.children) == 1:
        out.append(out[-1].parent)
    return list(reversed(out))


def limbs(rig):
    """A legs.Leg for each leg of `rig`, an armature named as lib/rigged.py names it."""
    out = []
    for paw in sorted((bone for bone in rig.data.bones if bone.name.split(".")[0].endswith("paw")),
                      key=lambda bone: bone.name):
        bones = _leg(paw)[:-1]
        if len(bones) < 2:
            raise ValueError("%s: a leg needs two bones above its paw to bend" % paw.name)
        top, foot = bones[0].head_local, paw.head_local
        # The knee: the joint farthest off the straight line from the leg's top to its paw.
        gaps = [((bone.tail_local - intersect_point_line(bone.tail_local, top, foot)[0]).length, index)
                for index, bone in enumerate(bones[:-1])]
        gap, knee = max(gaps)
        length = sum(bone.length for bone in bones)
        if gap < STRAIGHT * length:
            raise ValueError("%s: its leg is straight; it has no plane to bend in" % paw.name)
        bend = bones[knee].tail_local
        normal = (bend - top).cross(foot - bend).normalized()
        out.append(legs.Leg(tuple(bone.name for bone in bones[:knee + 1]),
                            tuple(bone.name for bone in bones[knee + 1:]), paw.name, plane=tuple(normal)))
    return out


def follow(rig):
    """motion.follow's chains for every stalk of `rig`: {bone: (frequency, damping, response,
    shift)}."""
    out = {}
    for first in (bone for bone in rig.data.bones if bone.name.split(".")[0].endswith("stalk_01")):
        frequency, damping, response, shift = STALK
        for index, bone in enumerate(_row(first)):
            out[bone.name] = (max(LOOSEST[0], frequency * LOOSER ** index),
                              max(LOOSEST[1], damping - WOBBLIER * index), response, shift)
    return out



class Body:
    """What clips.gait reads of a quadruped.Proportions, from an adopted rig named to the
    quadruped's scheme (`upper_arm`, `front_paw`, `thigh`, `hind_paw`, `hips`, `neck`), with
    the tip of its nose at `nose`. Its front leg starts at the `shoulder` bone, for a rig whose
    leg hangs from a shoulder blade (`scapula`)."""

    def __init__(self, rig, nose, shoulder="upper_arm"):
        bones = rig.data.bones
        self.front_leg = [tuple(bones["%s.L" % shoulder].head_local), tuple(bones["front_paw.L"].tail_local)]
        self.hind_leg = [tuple(bones["thigh.L"].head_local), tuple(bones["hind_paw.L"].tail_local)]
        self.hips = tuple(bones["hips"].head_local)
        self.chest = tuple(bones["neck"].head_local)
        self.nose = nose


def lesser(clip, share, turns=1.0, lift=1.0):
    """`clip` with its body's shifts, its paws' moves and its tail's swing `share` as large: for a
    body whose legs are short against the wolf's the library's clips are made for, which would
    reach too far for its hex. Its neck and head turn `turns` as far, and its paws' steps rise
    `lift` as high."""
    keys = []
    for key in clip.keys:
        pose = {name: tuple(share * value for value in values)
                if name == "root_loc" or name.startswith(("plant.", "tail_"))
                else tuple(turns * value for value in values) if name in ("neck", "head") else values
                for name, values in key[1].items()}
        keys.append((key[0], pose, *key[2:]))
    clip.keys = keys
    for step in clip.steps:
        step.spot = tuple(share * value for value in step.spot)
        step.height *= lift
    return clip
