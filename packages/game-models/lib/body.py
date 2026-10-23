"""Soft organic bodies from metaballs: balls, ellipsoids and capsules melt into one surface with
rounded joints and muscles, converted to a mesh and reduced to a triangle budget."""

import math

import bpy
from mathutils import Vector

from . import scene

# A lone metaball element's surface sits at this share of its radius (Blender's default threshold
# and stiffness); the helpers below take the surface size and scale by it.
SURFACE_SHARE = 0.574
# Blender's metaball field: an element of radius R adds STIFFNESS * (1 - d^2 / R^2)^3 at distance
# d, and the surface lies where the sum reaches THRESHOLD (its defaults).
STIFFNESS = 2.0
THRESHOLD = 0.6


def _line_radius(surface, spacing):
    """The radius each ball needs in a straight row of balls `spacing` apart for the row's
    surface to lie `surface` from its axis. Summed along the row, the balls' fields give
    STIFFNESS * 32/35 * (R^2 - surface^2)^(7/2) / (R^6 * spacing) there (the integral of one
    ball's field along the row, over the spacing); this solves it for R by bisection."""
    def field(radius):
        reach = radius * radius - surface * surface
        return STIFFNESS * 32.0 / 35.0 * reach ** 3.5 / (radius ** 6 * spacing)

    low, high = surface, surface * 4.0
    for _step in range(60):
        middle = (low + high) / 2
        low, high = (middle, high) if field(middle) < THRESHOLD else (low, middle)
    return (low + high) / 2


def _spline(points, share):
    """The point `share` of the way along a smooth curve through `points` (Catmull-Rom, its ends
    held), each point weighted equally."""
    spans = len(points) - 1
    index = min(int(share * spans), spans - 1)
    t = share * spans - index
    p0, p1, p2, p3 = (points[max(0, min(spans, index + k))] for k in (-1, 0, 1, 2))
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t)


class Blob:
    """A metaball body under construction. Sizes are the surface's, in metres."""

    def __init__(self, name, resolution=0.02):
        self.data = bpy.data.metaballs.new(name)
        self.data.resolution = resolution
        self.data.render_resolution = resolution
        self.obj = bpy.data.objects.new(name, self.data)
        bpy.context.collection.objects.link(self.obj)

    def ball(self, co, radius):
        element = self.data.elements.new(type="BALL")
        element.co = co
        element.radius = radius / SURFACE_SHARE
        return element

    def ellipsoid(self, co, half_extents, toward=None):
        """An ellipsoid with these half extents along X, Y, Z; with `toward`, its X axis turns to
        point that way (a muscle along a limb, a tail segment)."""
        element = self.data.elements.new(type="ELLIPSOID")
        element.co = co
        element.radius = 1.0 / SURFACE_SHARE
        element.size_x, element.size_y, element.size_z = half_extents
        if toward is not None:
            element.rotation = Vector(toward).to_track_quat("X", "Z")
        return element

    def capsule(self, a, b, radius):
        """A rounded rod from `a` to `b`."""
        a, b = Vector(a), Vector(b)
        element = self.data.elements.new(type="CAPSULE")
        element.co = (a + b) / 2
        element.radius = radius / SURFACE_SHARE
        element.size_x = (b - a).length / 2
        element.rotation = (b - a).to_track_quat("X", "Z")
        return element

    def limb(self, points, radii):
        """A tapering limb through `points`: a capsule per segment with a ball at each joint, so
        joints stay round (no point where a bent leg folds)."""
        for index, (a, b) in enumerate(zip(points, points[1:])):
            self.capsule(a, b, (radii[index] + radii[index + 1]) / 2)
        for point, radius in zip(points, radii):
            self.ball(point, radius)

    def tube(self, points, radii, spacing=0.3):
        """One smooth, tapering form along a curve through `points`, `radii` thick at them (a
        tail): a row of balls close together (`spacing` of the thinnest radius apart), each sized
        so the row's summed field lies at the radius wanted. A `limb`'s capsules and joint balls
        add up where they overlap and bulge into beads; an even row has nothing to bulge."""
        points = [Vector(point) for point in points]
        widths = [Vector((radius, 0.0, 0.0)) for radius in radii]  # the radii, as a curve too
        length = sum((b - a).length for a, b in zip(points, points[1:]))
        count = max(3, math.ceil(length / (spacing * min(radii))) + 1)
        shares = [index / (count - 1) for index in range(count)]
        centers = [_spline(points, share) for share in shares]
        for index, share in enumerate(shares):
            # The row runs faster or slower along the curve: each ball takes its own spacing.
            near = centers[max(0, index - 1):index + 2]
            gap = sum((b - a).length for a, b in zip(near, near[1:])) / (len(near) - 1)
            element = self.data.elements.new(type="BALL")
            element.co = centers[index]
            element.radius = _line_radius(max(_spline(widths, share).x, min(radii)), gap)

    def mesh(self, triangles):
        """The finished body: converted to a mesh, reduced to about `triangles`, smooth shaded."""
        scene.select_only(self.obj)
        bpy.ops.object.convert(target="MESH")
        body = bpy.context.object
        decimate = body.modifiers.new("Decimate", "DECIMATE")
        decimate.ratio = min(1.0, triangles / max(1, scene.triangles(body)))
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        bpy.ops.object.shade_smooth()
        return body
