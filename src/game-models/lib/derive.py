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


def whole(path, fps, name):
    """An empty scene with the original .glb (`path` from the repository's root) imported as one
    mesh part named `name`, its shape only: its parts joined and baked in place, the import's
    custom normals cleared, its seams welded and rebuilt in a fixed order, and no materials, so the
    derived model paints its own. For an original whose materials are painted on one mesh (the ore
    outcrop's stone, shaded stone and veins), which `original` refuses."""
    scene.reset(fps)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, path))
    meshes = sorted((obj for obj in bpy.data.objects if obj.type == "MESH"), key=lambda obj: obj.name)
    if not meshes:
        raise SystemExit("%s: no mesh to derive from" % path)
    for obj in meshes:
        obj.data.transform(obj.matrix_world)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    for obj in [obj for obj in bpy.data.objects if obj.type != "MESH"]:
        bpy.data.objects.remove(obj)
    target = meshes[0]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = target
    if len(meshes) > 1:
        bpy.ops.object.join()
    target.name = target.data.name = name
    scene.select_only(target)
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    target.data.materials.clear()
    # The import's materials and images go too, so the derived model's own take their names.
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for image in list(bpy.data.images):
        bpy.data.images.remove(image)

    def weld(work):
        fixed_order.weld(work)
        fixed_order.canonical(work)

    rebuild(target, weld)
    return target


def fracture(obj, seeds):
    """Splits a closed part into chunks, one per point of `seeds` (a Voronoi split): each chunk is
    the part cut at the plane halfway to every other seed, keeping the seed's side, its cuts closed
    with flat faces. Returns the chunks, new parts named after `obj` with a number, in the seeds'
    order; a seed whose cell misses the part gives none. `obj` itself is removed."""
    seeds = [Vector(seed) for seed in seeds]
    chunks = []
    for index, seed in enumerate(seeds):
        work = bmesh.new()
        work.from_mesh(obj.data)
        for other_index, other in enumerate(seeds):
            if other_index == index or not work.faces:
                continue
            fixed_order.cut(work, (seed + other) / 2.0, other - seed)
        if not work.faces:
            work.free()
            continue
        mesh = bpy.data.meshes.new("%s%02d" % (obj.name, index))
        work.to_mesh(mesh)
        work.free()
        chunk = bpy.data.objects.new(mesh.name, mesh)
        bpy.context.scene.collection.objects.link(chunk)
        rebuild(chunk, lambda work: fixed_order.canonical(work))
        chunks.append(chunk)
    bpy.data.objects.remove(obj)
    return chunks


def slump(chunks, spread, slide, keep, tilt):
    """Lets fractured chunks fall into a lower heap around the original's middle (its foot, the
    origin): each chunk tips about its own middle by up to `tilt` radians (the higher it stood the
    more, about a level axis across its way out, alternating sides chunk by chunk), slides out from
    the middle by `spread` times its distance from it plus `slide` times the height its foot stood
    at, and comes down until its foot keeps `keep` of that height (never below the ground). The
    chunks that stood on the ground stay on it. Moves their vertices; returns how far each chunk's
    top came down."""
    top = max(float(points(chunk)[:, 2].max()) for chunk in chunks)
    drops = []
    for index, chunk in enumerate(chunks):
        where = points(chunk)
        middle = Vector(where.mean(axis=0).tolist())
        low, high = float(where[:, 2].min()), float(where[:, 2].max())
        outward = Vector((middle.x, middle.y, 0.0))
        outward = outward.normalized() if outward.length > 1e-6 else Vector((1.0, 0.0, 0.0))
        side = 1.0 if index % 2 == 0 else -1.0
        turn = Matrix.Rotation(side * tilt * middle.z / top, 4, Vector((0.0, 0.0, 1.0)).cross(outward))
        chunk.data.transform(Matrix.Translation(middle) @ turn @ Matrix.Translation(-middle))
        away = Vector((middle.x, middle.y, 0.0)) * spread + outward * slide * low
        chunk.data.transform(Matrix.Translation(away))
        chunk.data.transform(Matrix.Translation((0.0, 0.0, keep * low - float(points(chunk)[:, 2].min()))))
        chunk.data.update()
        drops.append(high - float(points(chunk)[:, 2].max()))
    return drops


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
