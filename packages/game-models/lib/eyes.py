"""Detailed eyes that hold up close: a dark eyeball, a glowing iris with a slit pupil (no glint,
the owner on #1716), a glowing rim and a brow ridge over it, set into the head's surface and looking out and forward.
`almond` narrows the eye's height (1 is round) and `tilt` lifts its outer corner, so a predator's
eye reads sharp and angled rather than round.

An eye may have a lid (#1304): a dome of the head's skin over the eye on a bone of its own,
`lid.<side>`, hinged across the eye's middle. At rest it lies turned up and back over the eye, in
the head; turning its bone OPEN radians about its length (the eye's own sideways axis) brings it
down over the front of the eye, shut. `Lids` adds the bones and, as an animate overlay, shuts the
lids in its clips: asleep, fainted and blinking now and then while it stands."""

import math

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from . import parts, scene

LID = "lid."
# How far (radians) an open lid lies turned up and back from shut: its lower edge just over the
# eye's top, the dome tucked back into the head (and under a brow), so the open eye shows whole.
OPEN = math.radians(160)
# The lid's size against the eye's (sideways, up, out), the up share times `almond`: big enough
# shut to cover the eyeball, iris, pupil and the glowing rim round them. A round eye's lid is
# deeper (DEEP times `almond`): halfway shut, its depth stands up over the eye, and must still
# reach past the rim's top, or the rim shows above the lid in a blink (check_brows.py).
LID_SIZE = (1.25, 1.25, 0.95)
DEEP = 1.2
# How many times `eye` grows a lid that something pokes through, and by how much more than it
# pokes out (a share), so the lid clears it rather than touching it.
GROWS, MARGIN = 8, 0.03
# Marks a lid `mirrored` made from another (its custom property).
MIRROR = "mirrored"

def eye(body, name, guess, forward, size, mats, bone, almond=1.0, tilt=0.0, brow=0.0, brow_size=1.0,
        pupil=(0.16, 0.55), lid=None):
    """An eye on the body near `guess`, of radius `size`, looking between the surface's normal
    there and `forward`. `brow` angles the ridge over it down toward the snout (radians), and
    `brow_size` scales the ridge (1 is a predator's heavy brow; less for a softer, younger face),
    whose top edge stays above the eye. `pupil` is the pupil's (width, height) as shares of the
    eye: a predator's upright slit by default, wide and round for a gentler creature.
    `mats` needs "dark", "glow" and "skin" (the brow). Returns its pieces, all weighted to `bone`,
    and with a `lid` bone's name, the eye's lid, weighted to that bone (`Lids` adds it)."""
    found, location, normal, _index = body.closest_point_on_mesh(Vector(guess))
    normal = normal if found else Vector(forward)
    looking = (normal * 0.55 + Vector(forward).normalized() * 0.45).normalized()
    # pointing() builds a rotation, never a mirror, so the eye's own X runs toward the outer
    # corner on the left (+X) side and toward the inner corner on the right: `outer` turns every
    # sideways offset and angle around on the right, so the two eyes mirror each other exactly.
    outer = 1.0 if location.x >= 0.0 else -1.0
    turn = parts.pointing(looking).to_matrix() @ Matrix.Rotation(tilt * outer, 3, "Z")
    center = location - normal * size * 0.35

    def at(x, y, z):
        return center + turn @ (Vector((x * outer, y, z)) * size)

    rotation = turn.to_euler()
    iris = min(1.0, almond + 0.15)
    # A smaller ridge is thinner, but keeps most of its width and depth, and its top edge a little
    # above where the full one has it, over the eye's rim, so the eye never shows above its brow,
    # also with the head turned (the owner, on #1249; check_brows.py).
    keep = 0.5 + 0.5 * brow_size
    ridge = (1.45 * keep, 0.32 * brow_size, 0.7 * keep)
    lift = 0.4 * (1.0 - brow_size)
    pieces = [
        ("eyeball", "uv_sphere", at(0, 0, 0), (1.0, almond, 0.75), rotation, "dark"),
        ("iris", "uv_sphere", at(0, 0, 0.5), (0.7, 0.7 * iris, 0.28), rotation, "glow"),
        ("pupil", "uv_sphere", at(0, 0, 0.66), (pupil[0], pupil[1] * iris, 0.16), rotation, "dark"),
        ("brow", "uv_sphere", at(-0.05, 0.75 * almond + 0.12 + lift, 0.3), ridge,
         (turn @ Matrix.Rotation(brow * outer, 3, "Z")).to_euler(), "skin"),
    ]
    made = []
    for piece, kind, spot, scale, turned, mat in pieces:
        made.append(
            parts.part(kind, "%s.%s" % (name, piece), spot, [s * size for s in scale], turned,
                       mats[mat], bone, segments=12, ring_count=6)
        )
    made.append(
        parts.part("torus", name + ".rim", at(0, 0, 0.32), (size, size * almond, size), rotation,
                   mats["glow"], bone, major_radius=1.0, minor_radius=0.1, major_segments=16,
                   minor_segments=4)
    )
    if lid is not None:
        # A narrow eye's lid is thin across: halfway shut, its edge faces out where the pupil and
        # the iris stand out furthest, and they can poke through it (#1690). It's grown taller
        # (its depth, how far it bulges shut, stays) until nothing does.
        grow = 1.0
        cover = _lid(name + ".lid", center, turn, size, almond, mats["skin"], lid, grow)
        for _round in range(GROWS):
            reach = clipped(made + [cover])[0]
            if reach <= 0.0:
                break
            bpy.data.objects.remove(cover, do_unlink=True)
            grow *= (1.0 + reach) * (1.0 + MARGIN)
            cover = _lid(name + ".lid", center, turn, size, almond, mats["skin"], lid, grow)
        made.append(cover)
    return made


def _lid(name, center, turn, size, almond, mat, bone, grow=1.0):
    """The lid: the front half of a dome over the eye, flat across its back, turned OPEN up
    and back about the eye's sideways axis, its height times `grow`. Remembers its
    hinge and that axis (Lids)."""
    width, height, depth = LID_SIZE
    depth = max(depth, DEEP * almond)
    height = height * grow
    made = parts.part("uv_sphere", name, (0.0, 0.0, 0.0), (width * size, height * almond * size, depth * size),
                      mat=mat, bone=bone, segments=16, ring_count=8)
    # The back half pressed flat onto the front's rim: one closed piece, its faces as built, so
    # every build gives the same mesh (a filled hole's faces didn't, check_rebuild.py).
    for vertex in made.data.vertices:
        vertex.co.z = max(vertex.co.z, 0.0)
    made.data.transform(Matrix.Translation(center) @ (turn @ Matrix.Rotation(-OPEN, 3, "X")).to_4x4())
    made.data.update()
    made["hinge"], made["axis"] = tuple(center), tuple(turn @ Vector((1.0, 0.0, 0.0)))
    return made


# How far shut (shares of OPEN) `clipped` looks at a lid: open, every step of a blink, and shut.
SHARES = tuple(step / 20.0 for step in range(21))
# Closer to the lid than this share of its depth is touching it, not poking through (float noise
# where the shut lid meets the eyeball).
TOUCH = 1e-3


def clipped(pieces):
    """How far any piece of an eye built by `eye` with a lid pokes out through that lid at any
    of SHARES of its swing (#1690): a vertex outside the lid's closed mesh (its dome and flat
    back), on the side its dome covers, shows through it. Returns the worst as (how far out, a
    share of the lid's depth; the piece; the share), (0, None, None) when nothing pokes out. The
    eye `mirrored` makes is its left one's twin and isn't measured again; the brow lies over the
    lid, not under it, and is left out."""
    worst = (0.0, None, None)
    for lid in (piece for piece in pieces if "hinge" in piece and MIRROR not in piece):
        eye = lid.name[:-len("lid")]
        corners = [lid.matrix_world @ vertex.co for vertex in lid.data.vertices]
        shell = BVHTree.FromPolygons(corners, [polygon.vertices[:] for polygon in lid.data.polygons])
        hinge, axis = Vector(lid["hinge"]), Vector(lid["axis"])
        depth = max((corner - hinge).length for corner in corners)
        # Which way its dome bulges from its flat back, through the hinge.
        bulge = (sum(corners, Vector()) / len(corners) - hinge).normalized()
        spots = [(piece.name, piece.matrix_world @ vertex.co) for piece in pieces
                 if piece.name.startswith(eye) and piece is not lid and not piece.name.endswith(".brow")
                 for vertex in piece.data.vertices]
        for share in SHARES:
            # The lid's bone turns it OPEN * share about its axis from where it was built: the
            # pieces turned back as far meet the lid as built.
            back = Matrix.Rotation(-OPEN * share, 3, axis)
            for name, spot in spots:
                moved = back @ (spot - hinge) + hinge
                # Only where the dome covers it: behind the lid's flat back is the head, not the lid.
                if (moved - hinge).dot(bulge) <= 0.0:
                    continue
                location, normal, _index, distance = shell.find_nearest(moved)
                if location is None or (moved - location).dot(normal) <= 0.0:
                    continue
                if distance / depth > max(worst[0], TOUCH):
                    worst = (distance / depth, name, share)
    return worst


def mirrored(pieces):
    """The right eye of a left one `eyes.eye` built ("Eye.L.*"), mirrored across X (parts.mirrored),
    its lid on the right lid's bone, hinged on the right eye's own sideways axis."""
    made = []
    for piece in pieces:
        twin = parts.mirrored(piece, piece.name.replace(".L.", ".R."))
        if "hinge" in twin:
            # Its shape is the left lid's mirrored, which `clipped` measures there.
            twin[MIRROR] = True
            twin.vertex_groups[LID + "L"].name = LID + "R"
            x, y, z = piece["hinge"]
            twin["hinge"] = (-x, y, z)
            # The right eye's own X runs toward its inner corner (eye), so its axis is the left
            # one's mirrored and turned around.
            x, y, z = piece["axis"]
            twin["axis"] = (x, -y, -z)
        made.append(twin)
    return made


class Lids:
    """The lids' bones on `rig`, one per lid among `pieces` (`eyes.eye` with `lid`), hung from
    `parent` at the eye's middle and pointing along its sideways axis, in the rig's unscaled
    metres (before scene.apply_scale). `shut`, an animate overlay, closes them: all through Sleep,
    over `faint` (first frame, last frame) of Faint and held shut after, and in a blink at each
    share of Idle's loop in `blinks`, BLINK frames long."""

    # How many frames a blink takes, shut and open again: quick, and slow enough for the motion
    # check's jitter limit (shorter, the lid's swing starts and stops too sharply).
    BLINK = 12

    def __init__(self, rig, pieces, parent, faint, blinks=(0.3, 0.7)):
        self.faint, self.blinks = faint, blinks
        reach, piece, share = clipped(pieces)
        if reach > 0.0:
            raise ValueError("%s pokes %.0f%% out through its lid at %.2f shut" % (piece, 100 * reach, share))
        lids = sorted((piece for piece in pieces if "hinge" in piece), key=lambda piece: piece.name)
        self.names = [piece.vertex_groups[0].name for piece in lids]
        scene.select_only(rig)
        bpy.ops.object.mode_set(mode="EDIT")
        for name, piece in zip(self.names, lids):
            bone = rig.data.edit_bones.new(name)
            bone.head = Vector(piece["hinge"])
            bone.tail = Vector(piece["hinge"]) + Vector(piece["axis"]) * 0.02
            bone.parent = rig.data.edit_bones[parent]
        bpy.ops.object.mode_set(mode="OBJECT")

    def share(self, name, index, frame, frames):
        """How far shut (0..1) the lids are on `frame` of clip `name`, `index` frames into it,
        `frames` frames long."""
        if name == "Sleep":
            return 1.0
        if name == "Faint":
            start, end = self.faint
            # Smooth at both ends: a lid snapping shut at speed is a pop the motion check fails.
            done = max(0.0, min(1.0, (frame - start) / (end - start)))
            return done * done * (3.0 - 2.0 * done)
        if name == "Idle":
            shut = 0.0
            for at in self.blinks:
                since = index - round(at * frames)
                if 0 <= since <= self.BLINK:
                    shut += 0.5 - 0.5 * math.cos(2.0 * math.pi * since / self.BLINK)
            return shut
        return 0.0

    def shut(self, name, poses, loop):
        """Keys the lids on every frame of `poses` ([(frame, pose)], every frame)."""
        frames = len(poses) - 1 if loop else len(poses)
        for index, (frame, pose) in enumerate(poses):
            closed = self.share(name, index, frame, frames)
            for bone in self.names:
                pose[bone] = (0.0, OPEN * closed, 0.0)


def spot(pieces):
    """Where an eye built by `eye` looks out from: its iris's centre, for its attachment point
    (attachments.add)."""
    return next(piece for piece in pieces if piece.name.endswith(".iris")).location.copy()


def look(pieces):
    """Which way an eye built by `eye` looks out: from its eyeball's centre through its pupil, for
    its attachment point's direction (attachments.add)."""
    def center(piece):
        return next(made for made in pieces if made.name.endswith(piece)).location

    return (center(".pupil") - center(".eyeball")).normalized()
