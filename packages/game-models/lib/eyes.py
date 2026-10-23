"""Detailed eyes that hold up close: a dark eyeball, a glowing iris with a slit pupil, a glint, a
glowing rim and a brow ridge over it, set into the head's surface and looking out and forward.
`almond` narrows the eye's height (1 is round) and `tilt` lifts its outer corner, so a predator's
eye reads sharp and angled rather than round."""

from mathutils import Matrix, Vector

from . import parts

def eye(body, name, guess, forward, size, mats, bone, almond=1.0, tilt=0.0, brow=0.0, brow_size=1.0,
        pupil=(0.16, 0.55)):
    """An eye on the body near `guess`, of radius `size`, looking between the surface's normal
    there and `forward`. `brow` angles the ridge over it down toward the snout (radians), and
    `brow_size` scales the ridge (1 is a predator's heavy brow; less for a softer, younger face),
    whose top edge stays above the eye. `pupil` is the pupil's (width, height) as shares of the
    eye: a predator's upright slit by default, wide and round for a gentler creature.
    `mats` needs "dark", "glow", "light" and "skin" (the brow). Returns its pieces, all weighted to
    `bone`."""
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
        ("glint", "uv_sphere", at(0.25, 0.25 * almond, 0.74), (0.15, 0.15, 0.1), rotation, "light"),
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
    return made


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
