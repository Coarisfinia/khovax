"""A canine snout (#1026, #1194): the upper muzzle with its brow, stop, bridge and lips, and the
lower jaw with the cheeks over its back half, all melted into the head's metaball body as one skin,
the mouth a slit carved between the lips back to their corner; the jaw bone turns the skin below
the slit about the jaw joint far back on the skull, the cheek behind the corner stretching between
the jaws as it opens; the nose pad on its tip; the mouth's dark linings, which show only when it
opens; and the fangs.

Its parameters are what lib/metrics.py's snout measures read, so a model sets the snout it wants
and its build checks it: where the stop and the muzzle's tip are (its length), how wide it is at
the stop and how much of that is left at the tip (`taper`), how far the brow steps down to the
bridge (`stop_depth`), how far the lips hang below it (`lip`), and the lower jaw's depth and width
as shares of the upper muzzle's above it and how far toward the nose its chin reaches (`chin`).

Z up, facing -Y, mirrored across X = 0, as the body plans are; a point is its (y, z) on the
middle.

    snout = muzzle.Snout(stop=(-0.9, 1.5), tip=(-1.22, 1.37), radius=0.075, joint=(-0.74, 1.4))
    snout.upper(blob)  # into the head's body, before blob.mesh
    snout.lower(blob)
    pieces += snout.parts(mats, "head", "jaw")
    weights.bind(skin, rig, pieces, rigid_bones=("jaw", ...),
                 reweigh=lambda body: snout.bind_jaw(body, "jaw", scale))
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


def _limit(obj, vertex, keep, most=4):
    """Keeps a vertex's `most` strongest bones (as glTF carries them), always with the group
    `keep` among them, normalised."""
    groups = sorted(((group.group != keep, -group.weight, group.group) for group in vertex.groups))
    for _, _, index in groups[most:]:
        obj.vertex_groups[index].remove([vertex.index])
    total = -sum(weight for _, weight, _ in groups[:most])
    for _, weight, index in groups[:most]:
        obj.vertex_groups[index].add([vertex.index], -weight / total, "REPLACE")


def _smooth(x):
    """0 below 0, 1 above 1, and a smooth step between."""
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


class Snout:
    def __init__(self, stop, tip, radius, joint, taper=0.67, stop_depth=0.08, lip=0.04, jaw_depth=0.5,
                 jaw_width=0.85, chin=1.05, corner=0.1, tuck=0.25, slit=0.006):
        """`stop`: the bridge's top where the brow steps down to it; `tip`: the muzzle's front end,
        under the nose pad; `radius`: the muzzle's half width at the stop; `joint`: the jaw joint,
        on the skull's side below and before the ear, where the jaw bone turns the lower jaw (the
        bone's head belongs there). `chin` is how far along the muzzle (1 at its tip) the chin
        reaches, `corner` where the lips meet; `tuck` the share of the lower jaw's depth that
        hides inside the upper lip while the mouth is shut; `slit` how thick the mouth's slit is
        carved between the lips."""
        self.stop, self.tip, self.joint = _point(*stop), _point(*tip), _point(*joint)
        self.radius, self.taper, self.stop_depth, self.lip_drop = radius, taper, stop_depth, lip
        self.jaw_depth, self.jaw_width, self.chin, self.tuck = jaw_depth, jaw_width, chin, tuck
        self.corner, self.slit = corner, slit
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

    def mouth(self, t):
        """The mouth's line at `t`, where the lips part: between the upper lip's edge and the lower
        jaw's top, which tucks inside it. A straight line, from the corner to past the tip."""
        return self.lip(t).lerp(self.jaw_top(t), 0.5)

    def corner_point(self):
        """The mouth's corner, where the lips meet: on the mouth's line at `corner` along the
        muzzle."""
        return self.mouth(self.corner)

    def jaw_bottom(self):
        """The height of the lower jaw's lower edge at its back."""
        return self.jaw_top(0.0).z - 1.4 * self.jaw_half_depth(0.0)

    def lower(self, blob):
        """Adds the lower jaw to the head's `blob`, so it is one skin with the cheeks and the
        throat, as a wolf's furred jaw is: the jaw, as deep and wide as its shares of the upper
        muzzle above it, narrowing to a rounded chin at `chin` along the muzzle; the cheeks, the
        chewing muscle over the jaw's back from the mouth's corner to the joint, which hides the
        jaw's back half inside the head as a mandible's is; and the mouth, a thin slit carved
        between the lips from past the tip back to the corner, where it closes, so the lips part
        there and nowhere behind it."""
        for t in JAW_STATIONS:
            # Its back is shallower, so its lower edge curves up toward the joint; its underside
            # is round, its width narrowing with the muzzle's.
            half_depth = self.jaw_half_depth(t) * min(1.0, 0.7 + 1.2 * t)
            top = self.jaw_top(t)
            blob.ellipsoid((0.0, top.y, top.z - half_depth),
                           (self.radius * self.share(t) * self.jaw_width, self.length * JAW_SPAN, half_depth))
        half_depth = self.jaw_half_depth(self.chin)
        half_length = self.length * JAW_SPAN * 0.6
        top = self.jaw_top(self.chin)
        blob.ellipsoid((0.0, top.y + half_length, top.z - half_depth),
                       (self.radius * self.share(self.chin) * self.jaw_width * 0.85, half_length, half_depth))
        corner = self.corner_point()
        middle = corner.lerp(self.joint, 0.5)
        bottom = self.jaw_bottom()
        half_height = (self.joint.z - bottom) / 2
        half_length = (self.joint.y - corner.y) / 2
        for sign in (1, -1):
            blob.ellipsoid((sign * self.radius * self.jaw_width * 0.9, middle.y, bottom + half_height),
                           (self.radius * 0.8, half_length, half_height))
        # The slit: a flat, negative slab along the mouth's line, wider than the muzzle, its
        # rounded back edge at the corner.
        front = self.mouth(1.0 + 3.0 * JAW_SPAN)
        along = front - corner
        slit = blob.data.elements.new(type="PLANE")
        slit.use_negative = True
        # Stiff, so it cuts cleanly through where the jaw's top tucks into the upper lip.
        slit.stiffness = 10.0
        slit.co = corner + along * 0.5
        slit.radius = self.slit / body.SURFACE_SHARE
        slit.size_x, slit.size_y = 2.0 * self.radius, along.length / 2
        slit.rotation = Vector((0.0, -1.0, 0.0)).rotation_difference(-along)

    def bind_jaw(self, skin, jaw_bone, scale=1.0):
        """Hands the head's skin over the lower jaw to the jaw bone: below the mouth's line ahead
        of the corner, wholly; behind it, below the line from the corner to the joint, fading in
        over half the jaw's depth, so the cheek between the corner and the joint stretches as the
        jaw drops, as the skin over a mandible does; not below the jaw's lower edge, where the
        throat stays with the neck, nor behind the joint, fading out over the same distance past
        each, so the throat stretches a little where it meets the jaw. `skin` is the head's body
        with its automatic weights, before any piece joins it (weights.bind's `reweigh`), which
        has a `jaw_bone` group to fill; `scale` is what the model was shrunk by since it was
        built."""
        corner, joint = self.corner_point() * scale, self.joint * scale
        bottom = self.jaw_bottom() * scale
        fade = self.jaw_half_depth(0.0) * scale
        lips = (corner - self.mouth(1.0) * scale).normalized()
        cheek = (joint - corner).normalized()
        jaw = skin.vertex_groups.get(jaw_bone) or skin.vertex_groups.new(name=jaw_bone)
        for vertex in skin.data.vertices:
            weights = {group.group: group.weight for group in vertex.groups}
            offset = vertex.co - corner
            if vertex.co.y < corner.y:
                # Ahead of the corner the slit parts the lips: whatever lies below it is the jaw's.
                below = lips.y * offset.z - lips.z * offset.y
                share = _smooth(0.5 - below / (0.2 * fade))
            else:
                # How far below the corner-to-joint line, square to it.
                below = cheek.z * offset.y - cheek.y * offset.z
                share = (_smooth(below / fade) * (1.0 - _smooth((bottom - vertex.co.z) / fade))
                         * (1.0 - _smooth((vertex.co.y - joint.y) / fade)))
            if share <= 0.0:
                continue
            for index, weight in weights.items():
                skin.vertex_groups[index].add([vertex.index], weight * (1.0 - share), "REPLACE")
            jaw.add([vertex.index], share, "REPLACE")
            _limit(skin, vertex, jaw.index)

    def parts(self, mats, head_bone, jaw_bone, name="Snout"):
        """The pieces beside the head's skin: the mouth's floor and the lower fangs on `jaw_bone`;
        the palate, the nose pad and the upper fangs on `head_bone`. `mats` needs "dark" (the
        nose, the mouth) and "light" (the fangs)."""
        made = []
        # The mouth: dark, flat linings under the palate and over the jaw's floor, inside the lips
        # (and the jaw), so they show only when it opens.
        middle = self.chin * 0.42
        half_width = self.radius * self.share(middle) * 0.75
        half_length = self.length * self.chin * 0.5
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
