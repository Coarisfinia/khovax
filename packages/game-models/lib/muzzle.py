"""A canine snout (#1026): the upper muzzle with its brow, stop, bridge and lips, melted into a
head's metaball body; the nose pad on its tip; the lower jaw, a soft piece of its own that the jaw
bone opens; the mouth's dark lining, which shows only when it opens; and the fangs.

Its parameters are what lib/metrics.py's snout measures read, so a model sets the snout it wants
and its build checks it: where the stop and the muzzle's tip are (its length), how wide it is at
the stop and how much of that is left at the tip (`taper`), how far the brow steps down to the
bridge (`stop_depth`), how far the lips hang below it (`lip`), and the lower jaw's depth and width
as shares of the upper muzzle's above it and how far toward the nose its chin reaches (`chin`).

Z up, facing -Y, mirrored across X = 0, as the body plans are; a point is its (y, z) on the
middle.

    snout = muzzle.Snout(stop=(-0.9, 1.5), tip=(-1.22, 1.37), radius=0.075, hinge=(-0.8, 1.28))
    snout.upper(blob)  # into the head's body, before blob.mesh
    pieces += snout.parts(mats, "head", "jaw")
"""

from mathutils import Vector

from . import body, parts

# Where along the muzzle (0 at the stop, 1 at its tip) the lower jaw's body is laid, each part a
# soft ellipsoid reaching JAW_SPAN of the muzzle to either side: they overlap, so they melt into
# one smooth taper. The chin rounds it off past the last one.
JAW_STATIONS = (0.0, 0.25, 0.5, 0.75)
JAW_SPAN = 0.2


def _point(y, z):
    return Vector((0.0, y, z))


class Snout:
    def __init__(self, stop, tip, radius, hinge, taper=0.67, stop_depth=0.08, lip=0.04, jaw_depth=0.5,
                 jaw_width=0.85, chin=1.05, tuck=0.25, triangles=900):
        """`stop`: the bridge's top where the brow steps down to it; `tip`: the muzzle's front end,
        under the nose pad; `radius`: the muzzle's half width at the stop; `hinge`: where the lower
        jaw turns (the jaw bone's head). `chin` is how far along the muzzle (1 at its tip) the
        chin reaches; `tuck` the share of the lower jaw's depth that hides inside the upper lip
        while the mouth is shut. `triangles` is the lower jaw's budget."""
        self.stop, self.tip, self.hinge = _point(*stop), _point(*tip), _point(*hinge)
        self.radius, self.taper, self.stop_depth, self.lip_drop = radius, taper, stop_depth, lip
        self.jaw_depth, self.jaw_width, self.chin, self.tuck = jaw_depth, jaw_width, chin, tuck
        self.triangles = triangles
        self.length = self.stop.y - self.tip.y
        # The muzzle's core runs from the stop, a radius below the bridge, to the tip.
        self.core = self.stop - _point(0.0, radius)

    def share(self, t):
        """How much of the stop's width is left at `t` along the muzzle."""
        return 1.0 - (1.0 - self.taper) * t

    def top(self, t):
        """The bridge's top at `t`: a straight line from the stop to the tip's top."""
        return self.stop.lerp(self.tip + _point(0.0, self.radius * self.taper), t)

    def lip(self, t):
        """The upper lip's lower edge at `t`: `lip` below the core's underside at the stop, rising
        to the tip's underside."""
        return (self.core - _point(0.0, self.radius + self.lip_drop)).lerp(
            self.tip - _point(0.0, self.radius * self.taper), t)

    def depth(self, t):
        """The upper muzzle's depth at `t`, the bridge to the lip."""
        return self.top(t).z - self.lip(t).z

    def jaw_top(self, t):
        """The lower jaw's top at `t`, its `tuck` inside the upper lip."""
        return self.lip(t) + _point(0.0, self.depth(t) * self.jaw_depth * self.tuck)

    def upper(self, blob):
        """Adds the brow, the upper muzzle and its lips to the head's `blob`: a straight bridge
        stepping down `stop_depth` from the brow, narrowing toward the tip, with the lips hanging
        under its back half."""
        width = self.radius * 2
        blob.ellipsoid((0.0, self.stop.y + 0.5 * self.radius, self.stop.z + self.stop_depth - 0.8 * self.radius),
                       (1.6 * self.radius, width * 0.55, 0.8 * self.radius))
        middle = self.core.lerp(self.tip, 0.56)
        blob.capsule(self.core, middle, self.radius)
        blob.capsule(middle, self.tip, self.radius * self.taper)
        # A ridge down the middle keeps the bridge straight between the stop and the tip.
        ridge = 0.4 * self.radius
        blob.capsule(self.stop - _point(0.25 * self.radius, ridge),
                     self.top(0.94) - _point(0.0, ridge * 0.5), ridge)
        lips = self.core.lerp(self.tip, 0.31)
        blob.ellipsoid((0.0, lips.y, self.lip(0.31).z + self.lip_drop),
                       (0.73 * self.radius, 0.47 * self.length, self.lip_drop))

    def jaw_half_depth(self, t):
        """Half the lower jaw's depth at `t`: its share of the upper muzzle's there."""
        return self.depth(t) * self.jaw_depth / 2

    def _jaw(self, name, mat, bone):
        """The lower jaw: as deep and wide as its shares of the upper muzzle above it, from the
        hinge, where the cheeks hide it, to a rounded chin at `chin` along the muzzle."""
        blob = body.Blob(name)
        for t in JAW_STATIONS:
            # Its back rises toward the hinge (shallower there), so the jaw's lower edge runs
            # into the throat instead of ending in a bulge.
            half_depth = self.jaw_half_depth(t) * min(1.0, 0.7 + 1.2 * t)
            top = self.jaw_top(t)
            blob.ellipsoid((0.0, top.y, top.z - half_depth),
                           (self.radius * self.share(t) * self.jaw_width, self.length * JAW_SPAN, half_depth))
        # The chin: round, its front at `chin` along the muzzle.
        half_depth = self.jaw_half_depth(self.chin)
        half_length = self.length * JAW_SPAN * 0.6
        top = self.jaw_top(self.chin)
        blob.ellipsoid((0.0, top.y + half_length, top.z - half_depth),
                       (self.radius * self.share(self.chin) * self.jaw_width * 0.85, half_length, half_depth))
        radius = self.jaw_half_depth(0.0) * 0.6
        blob.capsule(self.hinge + _point(0.0, radius * 0.5), self.jaw_top(0.0) - _point(0.0, radius), radius)
        jaw = blob.mesh(self.triangles)
        jaw.name = name
        jaw.data.materials.append(mat)
        parts.weigh(jaw, bone)
        return jaw

    def parts(self, mats, head_bone, jaw_bone, name="Snout"):
        """The pieces beside the upper muzzle: the lower jaw with the mouth's floor and the lower
        fangs on `jaw_bone`; the palate, the nose pad and the upper fangs on `head_bone`. `mats`
        needs "fur", "dark" (the nose, the mouth) and "light" (the fangs)."""
        made = [self._jaw(name + ".Jaw", mats["fur"], jaw_bone)]
        # The mouth: dark, flat linings under the palate and over the jaw's floor, inside the lips
        # (and the jaw), so they show only when it opens.
        middle = self.chin * 0.5
        half_width = self.radius * self.share(middle) * 0.75
        half_length = self.length * self.chin * 0.42
        lining = 0.15 * self.radius
        for piece, at, bone in (("Palate", self.lip(middle) + _point(0.0, lining), head_bone),
                                ("Mouth", self.jaw_top(middle) - _point(0.0, lining * 0.5), jaw_bone)):
            made.append(parts.part("uv_sphere", "%s.%s" % (name, piece), at, (half_width, half_length, lining),
                                   mat=mats["dark"], bone=bone, segments=12, ring_count=6))
        made.append(parts.part("uv_sphere", name + ".Nose", self.tip + _point(-0.35 * self.radius, 0.35 * self.radius),
                               (0.56 * self.radius, 0.4 * self.radius, 0.35 * self.radius), (0.45, 0.0, 0.0),
                               mats["dark"], head_bone, segments=12, ring_count=6))
        # The canines: the upper ones behind the chin, just outside the lower jaw, so their tips
        # show over its lip; the lower ones ahead of them, inside the upper lip.
        fang = 0.55 * self.radius
        upper, lower = self.chin * 0.85, self.chin * 0.95
        for sign, side in ((1, "L"), (-1, "R")):
            base = self.lip(upper) + Vector((self.radius * self.share(upper) * 0.9 * sign, 0.0, fang * 0.3))
            made.append(parts.crystal("%s.Fang.%s" % (name, side), base, (0.0, 0.0, -1.0), fang, mats["light"],
                                      head_bone, width=0.25, sides=5))
            base = self.jaw_top(lower) + Vector((self.radius * self.share(lower) * self.jaw_width * 0.6 * sign, 0.0,
                                                 -fang * 0.3))
            made.append(parts.crystal("%s.LowFang.%s" % (name, side), base, (0.0, 0.0, 1.0), fang * 0.8,
                                      mats["light"], jaw_bone, width=0.25, sides=5))
        return made
