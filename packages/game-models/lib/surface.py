"""Patterns laid on a body's surface: glowing tubes that follow it (veins), and runes drawn
from strokes. They hug the surface (each point is pulled onto it and lifted by `lift`), and
weights.bind gives them the body's weights, so they bend with it."""

import math

import bpy
from mathutils import Vector

from . import scene

# Rune glyphs: strokes (polylines) in a square from -1 to 1, right and up.
GLYPHS = {
    "eye": [
        [(0.6 * math.cos(a * math.pi / 5), 0.6 * math.sin(a * math.pi / 5)) for a in range(11)],
        [(0.0, -1.0), (0.0, 1.0)],
    ],
    "fork": [[(0.0, -1.0), (0.0, 0.2)], [(-0.75, 1.0), (0.0, 0.2), (0.75, 1.0)]],
    "chevrons": [[(-0.8, 0.1), (0.0, 0.9), (0.8, 0.1)], [(-0.8, -0.7), (0.0, 0.1), (0.8, -0.7)]],
    "star": [[(-1.0, 0.0), (1.0, 0.0)], [(0.0, -1.0), (0.0, 1.0)], [(-0.6, -0.6), (0.6, 0.6)]],
    "wave": [[(-1.0, -0.2), (-0.5, 0.4), (0.0, -0.2), (0.5, 0.4), (1.0, -0.2)], [(0.0, -1.0), (0.0, -0.4)]],
}


def onto(body, point, lift):
    """`point` pulled onto the body's surface and lifted off it by `lift` along its normal."""
    found, location, normal, _index = body.closest_point_on_mesh(Vector(point))
    if not found:
        return Vector(point)
    return location + normal * lift


def _dense(points, step):
    """The polyline through `points` with extra points every `step`, so it can follow a curve."""
    out = [Vector(points[0])]
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        count = max(1, math.ceil((b - a).length / step))
        out += [a.lerp(b, (index + 1) / count) for index in range(count)]
    return out


def tube(name, points, radius, mat, shares=None):
    """A round tube along `points`, capped, as a mesh; with `shares`, each point's radius is that
    share of `radius`."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 1
    data.use_fill_caps = True
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for index, (spline_point, point) in enumerate(zip(spline.points, points)):
        spline_point.co = (point.x, point.y, point.z, 1.0)
        spline_point.radius = shares[index] if shares else 1.0
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    scene.select_only(obj)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    return obj


# The share of its radius a tapered vein keeps at its tip: thin enough to read as a point, wide
# enough that the tube's last ring doesn't collapse into one vertex.
TIP = 0.12


def _tapering(points, taper):
    """Each point's share of the radius along a vein whose last `taper` of its length narrows to a
    point, smoothly, so it fades into the skin rather than stopping blunt."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + (b - a).length)
    total = max(lengths[-1], 1e-9)
    shares = []
    for length in lengths:
        left = min(1.0, (total - length) / (total * taper))
        shares.append(TIP + (1.0 - TIP) * left * left * (3.0 - 2.0 * left))
    return shares


def vein(body, name, guide, radius, mat, lift=None, taper=0.0, smooth=0):
    """A glowing vein along the guide points, hugging the body. With `taper`, the last share of
    its length narrows to a point (a vein's loose end); without, it keeps its width (a rune's
    stroke). With `smooth`, it evens out that many times, each point toward its neighbours, so a
    thin line on a lumpy, reduced skin runs as a smooth curve rather than following every facet
    (#1294); its ends stay put."""
    lift = radius * 0.6 if lift is None else lift
    points = [onto(body, point, lift) for point in _dense(guide, radius * 6)]
    if not taper:
        return tube(name, _smoothed(points, smooth), radius, mat)
    # A narrowing end sinks with its width, so its tip lies on the skin rather than above it.
    shares = _tapering(points, taper)
    points = [onto(body, point, lift * share) for point, share in zip(points, shares)]
    return tube(name, _smoothed(points, smooth), radius, mat, shares)


def _smoothed(points, passes):
    """`points` evened out `passes` times, each toward its two neighbours; the ends stay put."""
    for _pass in range(passes):
        points = points[:1] + [(a + b * 2.0 + c) / 4.0 for a, b, c in zip(points, points[1:], points[2:])] + points[-1:]
    return points


def rune(body, name, glyph, center, right, up, size, radius, mat):
    """The glyph drawn on the body around `center`, its axes `right` and `up`, `size` across."""
    center, right, up = Vector(center), Vector(right), Vector(up)
    strokes = []
    for index, stroke in enumerate(GLYPHS[glyph]):
        guide = [center + (right * u + up * v) * (size / 2) for u, v in stroke]
        strokes.append(vein(body, "%s.%d" % (name, index), guide, radius, mat))
    return strokes
