"""Rigid parts: primitives placed, shaped and weighted whole to one bone (or left for
weights.bind to weight from the body they lie on), and the shaped pieces built from them."""

import math

import bpy
from mathutils import Matrix, Vector


def pointing(direction, up=(0.0, 0.0, 1.0)):
    """The rotation that turns a primitive's +Z toward `direction`, its +Y toward `up`."""
    direction = Vector(direction).normalized()
    side = Vector(up).cross(direction)
    if side.length < 1e-6:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    return Matrix((side, direction.cross(side), direction)).transposed().to_euler()


def weigh(obj, bone):
    """Weights every vertex of `obj` wholly to `bone`."""
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")


def part(kind, name, location, scale, rotation=(0.0, 0.0, 0.0), mat=None, bone=None, **shape):
    """A primitive (`kind`: cube, uv_sphere, cone, torus, ...) scaled in its own axes, then turned
    and placed. With no `bone`, weights.bind weights it from the body under it."""
    getattr(bpy.ops.mesh, "primitive_%s_add" % kind)(location=location, rotation=rotation, **shape)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if kind in ("uv_sphere", "torus", "cylinder", "cone"):
        bpy.ops.object.shade_smooth()
    if mat is not None:
        obj.data.materials.append(mat)
    if bone is not None:
        weigh(obj, bone)
    return obj


def crystal(name, base, direction, height, mat, bone=None, width=0.22, sides=6):
    """A faceted crystal: a prism that narrows to a point, growing from `base` toward
    `direction`, flat shaded so its facets catch the light."""
    shoulder = 0.65
    verts = []
    for radius, z in ((width, 0.0), (width * 1.15, shoulder)):
        for index in range(sides):
            angle = 2 * math.pi * index / sides
            verts.append((radius * height * math.cos(angle), radius * height * math.sin(angle), z * height))
    verts.append((0.0, 0.0, height))
    faces = [tuple(range(sides - 1, -1, -1))]
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((index, nxt, sides + nxt, sides + index))
        faces.append((sides + index, sides + nxt, 2 * sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.matrix_world = Matrix.Translation(base) @ pointing(direction).to_matrix().to_4x4()
    _bake(obj)
    obj.data.materials.append(mat)
    if bone is not None:
        weigh(obj, bone)
    return obj


def tuft(name, base, direction, length, width, bend, mat, bone=None, up=(0.0, 0.0, 1.0)):
    """A tuft of fur: a flattened cone from `base` toward `direction`, curling by `bend`
    radians toward its +Y side (`up`), so manes and ruffs read soft rather than spiky."""
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=1.0, radius2=0.0, depth=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.data.transform(Matrix.Translation((0.0, 0.0, 0.5)))
    obj.scale = (width, width * 0.45, length)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    curl = obj.modifiers.new("Curl", "SIMPLE_DEFORM")
    curl.deform_method = "BEND"
    curl.deform_axis = "X"
    curl.angle = bend
    bpy.ops.object.modifier_apply(modifier=curl.name)
    bpy.ops.object.shade_smooth()
    obj.matrix_world = Matrix.Translation(base) @ pointing(direction, up).to_matrix().to_4x4()
    _bake(obj)
    obj.data.materials.append(mat)
    if bone is not None:
        weigh(obj, bone)
    return obj


def _bake(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
