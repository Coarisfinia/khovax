"""The derive step (#2493): a changed object's "after" model made from its original's .glb, so it
matches the original exactly (the model skill's "after" rule, #2489). A derived model's script
names its original on a line of its own, `ORIGINAL = "<the .glb from the repository's root>"`,
which CI's model selection reads (changed_models.py): a change to the original rebuilds it, and a
stale derived .glb fails the rebuild check."""

import os

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

from . import fixed_order, scene

# The repository's root, from src/game-models/lib/.
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), *[os.pardir] * 3))


def original(path, fps):
    """An empty scene with the original .glb (`path` from the repository's root) imported: its mesh
    parts by name, each baked in place. The import's custom normals go (sort_mesh refuses them),
    and each part is rebuilt in a fixed order with its seams welded (fixed_order.canonical), flat
    shaded as our scripted props are, in its one material."""
    scene.reset(fps)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, path))
    parts = {}
    for obj in sorted((obj for obj in bpy.data.objects if obj.type == "MESH"), key=lambda obj: obj.name):
        if obj.parent is not None:
            raise SystemExit("%s: the derive step expects its original's parts side by side" % obj.name)
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        scene.select_only(obj)
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
        if len({polygon.material_index for polygon in obj.data.polygons}) != 1:
            raise SystemExit("%s: one material per part, so the part keeps it" % obj.name)
        rebuild(obj, lambda work: fixed_order.canonical(work))
        parts[obj.name] = obj
    return parts


def rebuild(obj, change):
    """Runs `change` on the part's bmesh and writes it back, flat shaded, all its faces in its one
    material."""
    work = bmesh.new()
    work.from_mesh(obj.data)
    change(work)
    for face in work.faces:
        face.material_index = 0
        face.smooth = False
    work.to_mesh(obj.data)
    work.free()
    obj.data.update()


def points(obj):
    return numpy.array([vertex.co[:] for vertex in obj.data.vertices])


def axis(obj):
    """A long part's axis: its vertices' main direction (pointing up) and its foot, the middle of
    its vertices lowest along that axis."""
    where = points(obj)
    middle = where.mean(axis=0)
    _values, vectors = numpy.linalg.eigh(numpy.cov((where - middle).T))
    direction = vectors[:, -1]
    if direction[2] < 0.0:
        direction = -direction
    along = (where - middle) @ direction
    foot = where[along <= along.min() + 1e-4].mean(axis=0)
    return Vector(foot.tolist()), Vector(direction.tolist()).normalized()


def stub(obj, top, tilt):
    """Breaks a long part off, leaving a short stub capped with flat faces: the cut goes through
    its axis where that rises to the height `top`, across it, tilted by `tilt` radians (its sign
    picks the side) so the break isn't a clean saw cut. A part that doesn't reach `top` stays
    whole. Returns how far along its axis the stub reaches."""
    foot, direction = axis(obj)
    if foot.z >= top or direction.z <= 0.0:
        raise SystemExit("%s: its foot isn't below the stub's top" % obj.name)
    reach = (top - foot.z) / direction.z
    across = direction.cross(Vector((0.0, 0.0, 1.0)))
    across = across.normalized() if across.length > 1e-6 else Vector((1.0, 0.0, 0.0))
    normal = Matrix.Rotation(tilt, 3, across) @ direction
    rebuild(obj, lambda work: fixed_order.cut(work, foot + direction * reach, normal))
    return reach
