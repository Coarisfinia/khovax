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


def tube(name, points, radius, mat):
    """A round tube along `points`, capped, as a mesh."""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = 1
    data.use_fill_caps = True
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for spline_point, point in zip(spline.points, points):
        spline_point.co = (point.x, point.y, point.z, 1.0)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    scene.select_only(obj)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    return obj


def vein(body, name, guide, radius, mat, lift=None):
    """A glowing vein along the guide points, hugging the body."""
    lift = radius * 0.6 if lift is None else lift
    points = [onto(body, point, lift) for point in _dense(guide, radius * 6)]
    return tube(name, points, radius, mat)


def rune(body, name, glyph, center, right, up, size, radius, mat):
    """The glyph drawn on the body around `center`, its axes `right` and `up`, `size` across."""
    center, right, up = Vector(center), Vector(right), Vector(up)
    strokes = []
    for index, stroke in enumerate(GLYPHS[glyph]):
        guide = [center + (right * u + up * v) * (size / 2) for u, v in stroke]
        strokes.append(vein(body, "%s.%d" % (name, index), guide, radius, mat))
    return strokes
