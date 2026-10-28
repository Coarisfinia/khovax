"""The starry egg (#1635): a cracked egg with a blob of night sky peeking out through the crack,
two pale eyes on it. Its mesh and the shell's colour come from the owner's generated model
(`sources/starry_egg.glb`, made by import_source.py from the download with its rig dropped: see
the asset's SOURCE.md). The blob inside gets our own starry sky (lib/starfield.py), drawn from a
fixed seed, instead of the generator's paint. A static model: no rig and no clips.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/starry_egg.py -- packages/game/assets/starry-egg/starry_egg.glb

Blender is Z-up and it faces -Y (the game's +Z); the origin is at the egg's foot, in the middle of
its hex. The source is already at the game's size (SCALE 1): it stands well inside its hex.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import scene, starfield  # noqa: E402

SOURCE = os.path.join(HERE, "sources", "starry_egg.glb")
FPS = 30
# Vertices closer than this are one (the export's seam splits), and an edge sharper than this
# angle stays sharp in the shading.
WELD = 1e-5
SHARP = math.radians(50.0)

# The blob's middle, roughly: of the source's three pieces (the shell's lower half, its cap and
# the blob between them), the blob is the one whose bounds' middle lies nearest it.
BLOB = (0.0, 0.0, 1.16)

# The sky: its size (twice as wide as tall, as a panorama is), seed and stars. Sizes are angles
# (radians) seen from the blob's middle; a texel is about 2 pi / SKY_WIDTH of them.
SKY_WIDTH, SKY_HEIGHT = 1024, 512
SEED = 1635
STARS = 260
SMALLEST, LARGEST = 0.013, 0.036
SPARKLES = 9
RAY = 0.11
# Stars only up to this sine of latitude: the shell hides the blob's top and bottom, where the
# panorama's columns crowd together.
POLAR = 0.85
# How much the sky glows on its own, so it reads as night inside the egg's shadow.
GLOW = 1.0

# The two pale eyes the generator painted on the blob's front, mirrored, kept as glowing discs.
EYE = (0.14, -0.46, 1.05)
EYE_COLOUR = (0.67, 0.89, 0.96)
EYE_RADIUS, EYE_EDGE = 0.055, 0.015


def blob_faces(mesh):
    """The faces of the piece (connected faces, welded by position) whose bounds' middle lies
    nearest BLOB."""
    work = bmesh.new()
    work.from_mesh(mesh)
    work.verts.ensure_lookup_table()
    # Pieces by position: the export splits a vertex wherever its UVs part (the seam splits).
    key = {vert.index: tuple(round(value, 5) for value in vert.co) for vert in work.verts}
    parent = {}

    def root(item):
        while parent.setdefault(item, item) != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    for face in work.faces:
        first = root(key[face.verts[0].index])
        for vert in face.verts[1:]:
            parent[root(key[vert.index])] = first
    pieces = {}
    for face in work.faces:
        pieces.setdefault(root(key[face.verts[0].index]), []).append(face)
    found = []
    for faces in pieces.values():
        points = numpy.array([vert.co[:] for face in faces for vert in face.verts])
        middle = (points.min(axis=0) + points.max(axis=0)) / 2.0
        found.append((float(numpy.linalg.norm(middle - BLOB)), sorted(face.index for face in faces)))
    work.free()
    return min(found)[1]


def sky():
    """The blob's texture: the starry sky, with its two eyes."""
    panorama = starfield.Sky(SKY_WIDTH, SKY_HEIGHT)
    panorama.background()
    starfield.stars(panorama, SEED, STARS, SMALLEST, LARGEST, SPARKLES, RAY, POLAR)
    return panorama


def main():
    out = sys.argv[sys.argv.index("--") + 1]
    scene.reset(FPS)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    egg = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    egg.name = egg.data.name = "StarryEgg"
    scene.select_only(egg)
    # The source's normals come back as custom ones, which sort_faces refuses (model skill).
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    # The export split every vertex where its UVs part; welded again, the shell shades smooth
    # across those seams instead of in patches (UVs live on the corners, so they stay). The
    # crack's jagged rim keeps its edges sharp.
    work = bmesh.new()
    work.from_mesh(egg.data)
    bmesh.ops.remove_doubles(work, verts=work.verts, dist=WELD)
    work.to_mesh(egg.data)
    work.free()
    bpy.ops.object.shade_smooth_by_angle(angle=SHARP)

    faces = blob_faces(egg.data)
    corners = numpy.array([vert.co[:] for vert in egg.data.vertices])
    blob_verts = sorted({index for face in faces for index in egg.data.polygons[face].vertices})
    centre = (corners[blob_verts].min(axis=0) + corners[blob_verts].max(axis=0)) / 2.0

    panorama = sky()
    for side in (1.0, -1.0):
        lon, lat = starfield.lonlat(side * EYE[0] - centre[0], EYE[1] - centre[1], EYE[2] - centre[2])
        panorama.stamp(lon, lat, EYE_RADIUS, starfield.disc(EYE_RADIUS, EYE_EDGE), EYE_COLOUR)
    image = bpy.data.images.new("starry_sky", SKY_WIDTH, SKY_HEIGHT, alpha=False)
    image.pixels.foreach_set(panorama.image().astype(numpy.float32).ravel())
    image.file_format = "PNG"
    image.pack()

    material = bpy.data.materials.new("starry_sky")
    material.use_backface_culling = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes["Principled BSDF"]
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    links.new(texture.outputs["Color"], shader.inputs["Emission Color"])
    shader.inputs["Emission Strength"].default_value = GLOW
    shader.inputs["Roughness"].default_value = 1.0
    egg.data.materials.append(material)
    slot = len(egg.data.materials) - 1

    # The blob is mapped around its middle: each corner's direction from it is where it lies on
    # the panorama, so the stars keep their shapes; a face across the seam behind (+Y) takes its
    # small u past 1, which the texture's repeat wraps.
    layer = egg.data.uv_layers.active.data
    for index in faces:
        polygon = egg.data.polygons[index]
        polygon.material_index = slot
        spots = []
        for loop in polygon.loop_indices:
            x, y, z = corners[egg.data.loops[loop].vertex_index] - centre
            spots.append(starfield.uv(x, y, z))
        if max(u for u, _ in spots) - min(u for u, _ in spots) > 0.5:
            spots = [(u + 1.0 if u < 0.5 else u, v) for u, v in spots]
        for loop, spot in zip(polygon.loop_indices, spots):
            layer[loop].uv = spot

    print("BUDGET triangles", scene.triangles(egg), "materials", len(egg.data.materials),
          "sky", "%dx%d" % (SKY_WIDTH, SKY_HEIGHT), "blob faces", len(faces),
          "centre", tuple(round(float(value), 3) for value in centre))
    scene.export_glb(out)


main()
