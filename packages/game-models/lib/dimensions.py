"""Whether a model's limbs have sane dimensions (the owner, on #1297: "add a check for
'weird-dimensions'", after the mana pup's forearms came out too long): each limb's segments
measured against each other and against how high the body stands, at rest, from the rig's joints
(the bones' heads, which a glTF import keeps exactly), so a fresh build and an imported .glb
measure alike.

Each body plan names its measures and the range each must stay in (BOUNDS). A measure reads the
joints `quadruped.armature` names; a rig without them (a body plan without legs) has nothing to
measure there and passes. The ranges are wide enough for the creatures the game has, from a
long-legged wolf to a squat toad, and narrow enough to catch a limb that reads as wrong:

- forearm/upper arm: the foreleg below the elbow against the leg above it. A canine's radius is
  about as long as its humerus; a toad's forearm is short. A forearm much longer than the upper
  arm looks stilted.
- shin/thigh: the hind leg below the knee against the thigh, the same way.
- foreleg/shoulder height: the foreleg's length, shoulder to wrist, against how high the shoulder
  stands. A straight leg under the shoulder is about as long as the shoulder is high, less the
  paw; much longer and the leg must bend at rest, much shorter and it can't reach the ground.

A hexapod (`hexapod.armature`, #1476) measures each pair's shin against its thigh: a leg whose
lower half is a stub or a stilt against its upper half reads as wrong on six legs as on four.

A hoofed quadruped (a foreleg with a `cannon.L` between its forearm and its hoof, #1619, such as
an adopted generated rig) measures the same three, with ranges of its own: the cannon (the long
bones of the foot) runs below the forearm, so the foreleg below the elbow is longer against the
upper arm than a canine's (a horse's about one and a half times), and the hock sits high, so the
shin is shorter against the thigh, the cannon below the hock taking up the length.

A measure is written as a number against its range ("forearm/upper arm 1.09, range 0.55 to
1.05"), never an adjective."""

# Each measure: (the joints whose distance is measured, the joints it's measured against), the
# left side's (the right mirrors it, which the symmetry check already holds), and the range it
# must stay in, per body plan.
MEASURES = {
    "forearm/upper arm": (("forearm.L", "front_paw.L"), ("upper_arm.L", "forearm.L")),
    "shin/thigh": (("shin.L", "hock.L"), ("thigh.L", "shin.L")),
    "foreleg/shoulder height": ((("upper_arm.L", "forearm.L"), ("forearm.L", "front_paw.L")), "upper_arm.L"),
    **{"%s shin/thigh" % pair: (("%s_shin.L" % pair, "%s_paw.L" % pair), ("%s_thigh.L" % pair, "%s_shin.L" % pair))
       for pair in ("front", "mid", "hind")},
}
BOUNDS = {
    "quadruped": {
        "forearm/upper arm": (0.55, 1.05),
        "shin/thigh": (0.8, 1.3),
        "foreleg/shoulder height": (0.6, 1.0),
    },
    "hoofed": {
        "forearm/upper arm": (0.9, 1.6),
        "shin/thigh": (0.7, 1.3),
        "foreleg/shoulder height": (0.6, 1.0),
    },
    "hexapod": {"%s shin/thigh" % pair: (0.6, 1.4) for pair in ("front", "mid", "hind")},
}
# The joints that make a rig a quadruped (quadruped.armature), and a hexapod (hexapod.armature).
QUADRUPED = ("upper_arm.L", "forearm.L", "front_paw.L", "thigh.L", "shin.L", "hock.L")
# A hoofed quadruped is a quadruped with a cannon between its forearm and its hoof.
HOOFED = "cannon.L"
HEXAPOD = tuple("%s_%s.L" % (pair, part) for pair in ("front", "mid", "hind") for part in ("thigh", "shin", "paw"))


def _head(rig, name):
    """Where the joint `name` is at rest, in the world: an imported rig may carry its axis
    conversion in its object's transform, so its own Z isn't always up."""
    return rig.matrix_world @ rig.data.bones[name].head_local


def _length(rig, pair):
    return (_head(rig, pair[0]) - _head(rig, pair[1])).length


def measure(rig, name):
    """The measure `name` (MEASURES) of `rig` at rest."""
    top, bottom = MEASURES[name]
    if name == "foreleg/shoulder height":
        # The shoulder's height above the ground under the feet: the rig's origin, at its feet.
        ground = rig.matrix_world.translation.z
        return sum(_length(rig, pair) for pair in top) / max(_head(rig, bottom).z - ground, 1e-6)
    return _length(rig, top) / max(_length(rig, bottom), 1e-6)


def body_plan(rig):
    """The body plan whose BOUNDS hold for `rig`, None when it has none of its limbs, or the
    joints a plan's limbs lack when it has only some of them (a renamed or missing bone)."""
    names = rig.data.bones.keys()
    lacking = [name for name in HEXAPOD if name not in names]
    if not lacking:
        return "hexapod"
    # A quadruped shares its paws' names with a hexapod: only the middle pair is a hexapod's own.
    if any(name in names for name in HEXAPOD if name.startswith("mid_")):
        return lacking
    lacking = [name for name in QUADRUPED if name not in names]
    if not lacking:
        return "hoofed" if HOOFED in names else "quadruped"
    return None if len(lacking) == len(QUADRUPED) else lacking


def report(rig):
    """Each measure of `rig`'s body plan against its range. Returns (lines, passed); a rig of no
    body plan in BOUNDS has nothing to measure and passes, and one with only some of a
    quadruped's or a hexapod's limb joints fails."""
    plan = body_plan(rig)
    if plan is None:
        return ["no limbs of a known body plan: nothing to measure"], True
    if isinstance(plan, list):
        return ["FAIL limbs lacking the joints " + ", ".join(plan)], False
    lines, passed = [], True
    for name, (low, high) in BOUNDS[plan].items():
        value = measure(rig, name)
        ok = low <= value <= high
        passed = passed and ok
        lines.append("%s %s %s: %.2f, range %.2f to %.2f" % ("ok" if ok else "FAIL", plan, name, value, low, high))
    return lines, passed
