"""Proportions as numbers (#1072), so a derpy model fails a check instead of slipping past the eye.
A model script keeps a `REFERENCE` dict of its approved proportions (ratios, so the model's scale
doesn't matter), and `check` measures the built rig and mesh at rest against it, like the ground
check: a line per measure, written as a measurement ("head/body 12 % too large"), never an
adjective, and a fail beyond the tolerance.

The measures read only bone heads (the joints, which a glTF import keeps exactly) and the rest
mesh each bone moves most, so they measure a freshly built model and an imported .glb alike. A
measure whose bones the rig lacks is skipped with a note: a body plan without legs simply keeps
those out of its REFERENCE.

    REFERENCE = {"head/body": 0.62, "eye.R/eye.L height": 0.0, ...}
    lines, passed = metrics.check(rig, [skin], REFERENCE)
"""

from . import pulse

# How far a ratio may drift from its reference, as a share of it (a proportion within 5 %, the
# blockout gate of the sources on #1072).
TOLERANCE = 0.05
# How far a symmetry measure (whose reference is 0) may stray, as a share of the head's length.
SYMMETRY_TOLERANCE = 0.02


# Everything is measured in the rig's own space, so where the rig stands doesn't matter: its X = 0
# is the plane the left and right sides mirror across, and its Z = 0 the ground under the feet.


def _joint(rig, name):
    bone = rig.data.bones.get(name)
    return None if bone is None else bone.head_local.copy()


def _owned(rig, meshes, bones):
    """The rest positions of the vertices each bone in `bones` moves most, a pulsing part's bone
    (pulse.Pulse) counting as its parent's, whose part it is."""
    bones = set(bones) | {bone.name for bone in rig.data.bones
                          if bone.name.startswith(pulse.PREFIX) and bone.parent is not None and bone.parent.name in bones}
    to_rig = rig.matrix_world.inverted()
    points = []
    for obj in meshes:
        groups = {group.index for group in obj.vertex_groups if group.name in bones}
        for vertex in obj.data.vertices:
            if vertex.groups and max(vertex.groups, key=lambda g: g.weight).group in groups:
                points.append(to_rig @ obj.matrix_world @ vertex.co)
    return points


def _extent(points, axis):
    values = [point[axis] for point in points]
    return max(values) - min(values) if values else None


class Body:
    """The quadruped's lengths the measures are made of, each None when the rig lacks its bones."""

    def __init__(self, rig, meshes):
        hips, chest = _joint(rig, "hips"), _joint(rig, "neck")
        head = _owned(rig, meshes, {"head"})
        # The torso, along the spine: the hips to the base of the neck.
        self.body = abs(hips.y - chest.y) if hips is not None and chest is not None else None
        # The head's skin (jaw and ears are their own bones): long along the facing axis (Y),
        # tall, and wide across.
        self.head_length = _extent(head, 1)
        self.head_height = _extent(head, 2)
        self.head_width = _extent(head, 0)
        # The front leg's height: the shoulder above the bottom of its paw.
        shoulder = _joint(rig, "upper_arm.L")
        paw = _owned(rig, meshes, {"front_paw.L"})
        self.leg = shoulder.z - min(point.z for point in paw) if shoulder is not None and paw else None
        self.ear = self._reach(rig, meshes, "ear.L", {"ear.L"})
        tail_bones = {bone.name for bone in rig.data.bones if bone.name.startswith("tail_")}
        self.tail = self._reach(rig, meshes, "tail_01", tail_bones)
        self.eyes = (_joint(rig, "eye.L"), _joint(rig, "eye.R"))
        self.eye_spacing = None if None in self.eyes else (self.eyes[0] - self.eyes[1]).length
        self.snout = Snout(head, _owned(rig, meshes, {"jaw"}), self.eyes[0])

    @staticmethod
    def _reach(rig, meshes, root, bones):
        """How far the mesh `bones` move reaches from `root`'s joint: an ear's or a tail's length."""
        start = _joint(rig, root)
        points = _owned(rig, meshes, bones)
        return max((point - start).length for point in points) if start is not None and points else None


class Snout:
    """The snout's lengths (#1026): the upper muzzle (the head's skin ahead of the eyes, the stop
    to the nose) and the lower jaw (the skin the jaw moves), each measured across at the muzzle's
    middle, where a wolf's snout is judged; and the nose's tip, the front of the muzzle. Each is
    None when the rig lacks a jaw or eyes, or the jaw has no skin there."""

    # How much of the muzzle's length the middle and the tip span.
    MIDDLE = 0.2
    TIP = 0.15

    def __init__(self, head, jaw, eye):
        self.length = self.depth = self.width = self.tip_width = None
        self.jaw_length = self.jaw_depth = self.jaw_width = self.chin = None
        if eye is None or not head:
            return
        # The wolf faces -Y: ahead of the eyes is a smaller Y.
        muzzle = [point for point in head if point.y < eye.y]
        if not muzzle:
            return
        nose = min(point.y for point in muzzle)
        self.length = eye.y - nose
        middle = eye.y - self.length / 2
        band = self.length * self.MIDDLE / 2
        across = [point for point in muzzle if abs(point.y - middle) <= band]
        self.depth, self.width = _extent(across, 2), _extent(across, 0)
        self.tip_width = _extent([point for point in muzzle if point.y <= nose + self.length * self.TIP], 0)
        if not jaw:
            return
        self.jaw_length = _extent(jaw, 1)
        # How far ahead of the eyes the chin reaches: the muzzle's length when it meets the nose.
        self.chin = eye.y - min(point.y for point in jaw)
        across = [point for point in jaw if abs(point.y - middle) <= band]
        self.jaw_depth, self.jaw_width = _extent(across, 2), _extent(across, 0)


def _ratio(top, bottom):
    return None if top is None or not bottom else top / bottom


def _eyes(body, between):
    left, right = body.eyes
    if body.eye_spacing is None or not body.head_length:
        return None
    return between(left, right) / body.head_length


# Each measure: (what it compares, how it's measured). A ratio's reference is the approved value;
# a symmetry measure's is 0 (the eyes mirror each other), in the head's lengths.
RATIOS = {
    "head/body": lambda b: _ratio(b.head_length, b.body),
    "head height/length": lambda b: _ratio(b.head_height, b.head_length),
    "head width/length": lambda b: _ratio(b.head_width, b.head_length),
    "leg/body": lambda b: _ratio(b.leg, b.body),
    "ear/head": lambda b: _ratio(b.ear, b.head_length),
    "tail/body": lambda b: _ratio(b.tail, b.body),
    "eye spacing/head width": lambda b: _ratio(b.eye_spacing, b.head_width),
    # The snout (#1026), against the head and against itself, as a wolf's is judged: its length
    # against the head's, how deep and wide it is, how it narrows to the nose, and the lower jaw
    # against the upper muzzle (as deep, as wide, as long, and how far forward the chin reaches).
    "muzzle/head": lambda b: _ratio(b.snout.length, b.head_length),
    "muzzle depth/length": lambda b: _ratio(b.snout.depth, b.snout.length),
    "muzzle width/head width": lambda b: _ratio(b.snout.width, b.head_width),
    "nose width/muzzle width": lambda b: _ratio(b.snout.tip_width, b.snout.width),
    "jaw depth/muzzle depth": lambda b: _ratio(b.snout.jaw_depth, b.snout.depth),
    "jaw width/muzzle width": lambda b: _ratio(b.snout.jaw_width, b.snout.width),
    "jaw/muzzle": lambda b: _ratio(b.snout.jaw_length, b.snout.length),
    "chin reach/muzzle": lambda b: _ratio(b.snout.chin, b.snout.length),
}
SYMMETRY = {
    # Mirrored across X, so their heights and depths match and their sides cancel.
    "eye.R/eye.L height": lambda b: _eyes(b, lambda l, r: r.z - l.z),
    "eye.R/eye.L depth": lambda b: _eyes(b, lambda l, r: r.y - l.y),
    "eye.R/eye.L sides": lambda b: _eyes(b, lambda l, r: l.x + r.x),
}


def measure(rig, meshes):
    """Every measure by name, None where the rig lacks its bones."""
    body = Body(rig, meshes)
    return {name: rule(body) for name, rule in (RATIOS | SYMMETRY).items()}


def check(rig, meshes, reference):
    """Measures `rig` and `meshes` at rest against `reference` (name: value). Returns (lines,
    passed): a line per measure and whether every one is within its tolerance. A reference naming
    a measure the model can't take fails too, rather than passing unseen."""
    found = measure(rig, meshes)
    lines = []
    passed = True
    for name in sorted(found.keys() | reference.keys()):
        value, wanted = found.get(name), reference.get(name)
        if wanted is None:
            taken = "can't be measured on this rig" if value is None else "%.3f" % value
            lines.append("note %s: %s (not in REFERENCE)" % (name, taken))
            continue
        if value is None:
            lines.append("FAIL %s: can't be measured on this rig" % name)
            passed = False
            continue
        if name in SYMMETRY:
            off = value - wanted
            ok = abs(off) <= SYMMETRY_TOLERANCE
            text = "%.3f, reference %.3f: off by %.1f %% of the head's length" % (value, wanted, off * 100)
        else:
            off = value / wanted - 1.0
            ok = abs(off) <= TOLERANCE
            text = "%.3f, reference %.3f: %.1f %% too %s" % (value, wanted, abs(off) * 100,
                                                             "large" if off > 0 else "small")
        passed = passed and ok
        lines.append("%s %s: %s" % ("ok" if ok else "FAIL", name, text))
    return lines, passed


def report(rig, meshes, reference):
    """Prints `check`'s lines like the ground check and returns whether it passed."""
    lines, passed = check(rig, meshes, reference)
    for line in lines:
        print("PROPORTIONS", line)
    print("PROPORTIONS CHECK:", "PASS" if passed else "FAIL",
          "(tolerance %d %%, symmetry %d %% of the head)" % (TOLERANCE * 100, SYMMETRY_TOLERANCE * 100))
    return passed

