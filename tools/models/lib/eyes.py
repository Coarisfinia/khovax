"""Detailed eyes that hold up close: a dark eyeball, a glowing iris with a slit pupil, a glint, a
glowing rim and a brow ridge over it, set into the head's surface and looking out and forward.
`almond` narrows the eye's height (1 is round) and `tilt` lifts its outer corner, so a predator's
eye reads sharp and angled rather than round."""

from mathutils import Matrix, Vector

from . import parts

def eye(body, name, guess, forward, size, mats, bone, almond=1.0, tilt=0.0, brow=0.0):
    """An eye on the body near `guess`, of radius `size`, looking between the surface's normal
    there and `forward`. `brow` angles the ridge over it down toward the snout (radians).
    `mats` needs "dark", "glow", "light" and "skin" (the brow). Returns its pieces, all weighted to
    `bone`."""
    found, location, normal, _index = body.closest_point_on_mesh(Vector(guess))
    normal = normal if found else Vector(forward)
    looking = (normal * 0.55 + Vector(forward).normalized() * 0.45).normalized()
    # The eye's own X runs toward its outer corner (back along the head) for either eye, so one
    # tilt lifts both outer corners.
    turn = parts.pointing(looking).to_matrix() @ Matrix.Rotation(tilt, 3, "Z")
    center = location - normal * size * 0.35

    def at(x, y, z):
        return center + turn @ (Vector((x, y, z)) * size)

    rotation = turn.to_euler()
    iris = min(1.0, almond + 0.15)
    pieces = [
        ("eyeball", "uv_sphere", at(0, 0, 0), (1.0, almond, 0.75), rotation, "dark"),
        ("iris", "uv_sphere", at(0, 0, 0.5), (0.7, 0.7 * iris, 0.28), rotation, "glow"),
        ("pupil", "uv_sphere", at(0, 0, 0.66), (0.16, 0.55 * iris, 0.16), rotation, "dark"),
        ("glint", "uv_sphere", at(0.25, 0.25 * almond, 0.74), (0.15, 0.15, 0.1), rotation, "light"),
        ("brow", "uv_sphere", at(-0.05, 0.75 * almond + 0.12, 0.3), (1.45, 0.32, 0.7),
         (turn @ Matrix.Rotation(brow, 3, "Z")).to_euler(), "skin"),
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
