"""Mirror symmetry: every left part (a name with an `L` part, like `Eye.L.brow` or
`Claw.hind_paw.L.2`) must be its right twin (`R` in its place) mirrored across X, so a sideways
offset or an angle that isn't mirrored can't sneak in. Run it on the parts before they are
joined; parts without a side are left alone."""

import re

from mathutils import Vector

SIDE = re.compile(r"(?<=\.)L(?=\.|$)")


def _extent(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    low = Vector([min(p[axis] for p in points) for axis in range(3)])
    high = Vector([max(p[axis] for p in points) for axis in range(3)])
    centre = sum(points, Vector()) / len(points)
    return low, high, centre


def report(objects, tolerance=0.01):
    """Lines naming every left part whose mirrored bounds or centre miss its right twin's by more
    than `tolerance` (or that has no twin), and whether all of them match."""
    by_name = {obj.name: obj for obj in objects}
    lines = []
    for name, left in sorted(by_name.items()):
        if not SIDE.search(name):
            continue
        right = by_name.get(SIDE.sub("R", name))
        if right is None:
            lines.append("NO TWIN %s" % name)
            continue
        low, high, centre = _extent(left)
        r_low, r_high, r_centre = _extent(right)
        mirrored = (Vector((-high.x, low.y, low.z)), Vector((-low.x, high.y, high.z)),
                    Vector((-centre.x, centre.y, centre.z)))
        miss = max((a - b).length for a, b in zip(mirrored, (r_low, r_high, r_centre)))
        if miss > tolerance:
            lines.append("ASYMMETRIC %s: %.3f off its twin" % (name, miss))
    return lines, not lines


def check(objects, tolerance=0.01):
    """Raises, naming them, when any left part isn't its right twin mirrored."""
    lines, passed = report(objects, tolerance)
    for line in lines:
        print("SYMMETRY", line)
    print("SYMMETRY CHECK:", "PASS" if passed else "FAIL")
    if not passed:
        raise RuntimeError("left and right parts don't mirror each other")
