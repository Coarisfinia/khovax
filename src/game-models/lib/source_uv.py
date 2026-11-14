"""A generated model's own UVs back onto pieces cut from it (#1836): lib/fixed_order.py's steps
keep only positions and faces, which is all a prop painted from the shared texture set needs, but a
model that keeps the generator's paint needs its UVs.

`transfer` gives each face of a piece, still where it lay in the source, the UVs its corners have on
the source face under its middle: a cut face lies inside the source face it was cut from, so its
corners land inside that face too, and a face never takes UVs across one of the atlas's seams. The
faces closing a cut lie inside the model, where no source face is: they take whatever face is
nearest, and stay out of sight (a joint, the foot standing on the ground).

Blender's BVH tree and barycentric maths are single-threaded and the UVs are rounded, so a build on
another machine gives the same bytes."""

import bmesh
from mathutils import geometry
from mathutils.bvhtree import BVHTree

# The UV layer glTF's import and export name.
LAYER = "UVMap"
# The UVs are rounded to this many decimals (a texel of a 1024 atlas is about 0.001).
DECIMALS = 6


class Source:
    """The source mesh's triangles and their corners' UVs, and a tree to find the one under a point."""

    def __init__(self, mesh):
        work = bmesh.new()
        work.from_mesh(mesh)
        bmesh.ops.triangulate(work, faces=work.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")
        layer = work.loops.layers.uv[LAYER]
        self.corners = [[(loop.vert.co.copy(), loop[layer].uv.copy()) for loop in face.loops] for face in work.faces]
        self.tree = BVHTree.FromBMesh(work)
        work.free()

    def uv(self, face_index, point):
        """The UV at `point` on (or near) the source triangle `face_index`."""
        (a, ua), (b, ub), (c, uc) = self.corners[face_index]
        mapped = geometry.barycentric_transform(point, a, b, c, ua.to_3d(), ub.to_3d(), uc.to_3d())
        return round(mapped.x, DECIMALS), round(mapped.y, DECIMALS)


def transfer(work, source):
    """Gives the bmesh `work`, lying where it lay in `source` (a `Source`), a UV layer from it."""
    layer = work.loops.layers.uv.get(LAYER) or work.loops.layers.uv.new(LAYER)
    for face in work.faces:
        _location, _normal, index, _distance = source.tree.find_nearest(face.calc_center_median())
        for loop in face.loops:
            loop[layer].uv = source.uv(index, loop.vert.co)
