"""Detailed eyes that hold up close: a dark eyeball, a glowing iris with a slit pupil, a glint, a
glowing rim and a heavy upper lid, set into the head's surface and looking out and forward."""

from mathutils import Vector

from . import parts, surface


def eye(body, name, guess, forward, size, mats, bone):
    """An eye on the body near `guess`, of radius `size`, looking between the surface's normal
    there and `forward`. `mats` needs "dark", "glow", "light" and "skin" (the lid). Returns its
    pieces, all weighted to `bone`."""
    found, location, normal, _index = body.closest_point_on_mesh(Vector(guess))
    normal = normal if found else Vector(forward)
    looking = (normal * 0.55 + Vector(forward).normalized() * 0.45).normalized()
    turn = parts.pointing(looking).to_matrix()
    center = location - normal * size * 0.35

    def at(x, y, z):
        return center + turn @ (Vector((x, y, z)) * size)

    rotation = turn.to_euler()
    pieces = [
        ("eyeball", "uv_sphere", at(0, 0, 0), (1.0, 1.0, 0.75), "dark"),
        ("iris", "uv_sphere", at(0, 0, 0.5), (0.78, 0.78, 0.28), "glow"),
        ("pupil", "uv_sphere", at(0, 0, 0.66), (0.2, 0.58, 0.16), "dark"),
        ("glint", "uv_sphere", at(0.28, 0.32, 0.74), (0.17, 0.17, 0.1), "light"),
        ("lid", "uv_sphere", at(0, 0.62, 0.22), (1.25, 0.55, 0.78), "skin"),
    ]
    made = []
    for piece, kind, location_, scale, mat in pieces:
        made.append(
            parts.part(kind, "%s.%s" % (name, piece), location_, [s * size for s in scale], rotation,
                       mats[mat], bone, segments=12, ring_count=6)
        )
    made.append(
        parts.part("torus", name + ".rim", at(0, 0, 0.32), (size, size, size), rotation, mats["glow"],
                   bone, major_radius=1.0, minor_radius=0.1, major_segments=16, minor_segments=4)
    )
    return made
