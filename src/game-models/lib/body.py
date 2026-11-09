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
# How finely `Blob.tube` samples its curve to space its balls evenly along it.
FINE = 1000


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
        # The curve's length along it, finely sampled, so the balls lie evenly spaced along it
        # whatever its spans' lengths: (share of the curve's parameter, length so far).
        fine = [index / FINE for index in range(FINE + 1)]
        along = [0.0]
        for a, b in zip(fine, fine[1:]):
            along.append(along[-1] + (_spline(points, b) - _spline(points, a)).length)
        count = max(3, math.ceil(along[-1] / (spacing * min(radii))) + 1)
        gap = along[-1] / (count - 1)
        span = 0
        for index in range(count):
            wanted = gap * index
            while span < FINE - 1 and along[span + 1] < wanted:
                span += 1
            within = (wanted - along[span]) / max(along[span + 1] - along[span], 1e-12)
            share = fine[span] + min(1.0, within) / FINE
            element = self.data.elements.new(type="BALL")
            element.co = _spline(points, share)
            element.radius = _line_radius(max(_spline(widths, share).x, min(radii)), gap)

    def mesh(self, triangles, symmetric=False):
        """The finished body: converted to a mesh, reduced to about `triangles`, smooth shaded.
        `symmetric` reduces its two halves alike, mirrored across X, so what is set into its
        surface on one side (an eye in its socket) sits in the other side alike."""
        scene.select_only(self.obj)
        bpy.ops.object.convert(target="MESH")
        body = bpy.context.object
        decimate = body.modifiers.new("Decimate", "DECIMATE")
        decimate.ratio = min(1.0, triangles / max(1, scene.triangles(body)))
        decimate.use_symmetry = symmetric
        decimate.symmetry_axis = "X"
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        bpy.ops.object.shade_smooth()
        return body
