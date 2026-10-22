"""Soft organic bodies from metaballs: balls, ellipsoids and capsules melt into one surface with
rounded joints and muscles, converted to a mesh and reduced to a triangle budget."""

import bpy
from mathutils import Vector

from . import scene

# A lone metaball element's surface sits at this share of its radius (Blender's default threshold
# and stiffness); the helpers below take the surface size and scale by it.
SURFACE_SHARE = 0.574


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
