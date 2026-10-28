"""Turns a textured model from a generator's download into the source a model script builds from
(#1476): its mesh with its UVs and only its base colour texture, its longer side shrunk to
`size`, opaque, single-sided and matte. A generator's export carries far more than the game's
cel look shows (a normal map, a metal and roughness map, each as large as the colour), and the
game's other models are a small share of its size; the model script then places, rigs and
animates the source.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/import_source.py -- <download.glb> <source.glb> [size=1024]

An unrigged download's source keeps its axes and origin: the model script places it on its feet.

A download the generator has already rigged (#1516) keeps its skin and its rig, adopted by
lib/rigged.py: its chains checked against the parts they move and fixed, its bones named to the
library's scheme and the model placed on its feet, hung from a root between them. It prints
what it kept, fixed and renamed.

`scale` sizes it before any clip exists (#1522), since the gait's limits depend on the size and a
later rescale redoes the gait and every render: `hex` (the default) fits it to its hex as a regular
monster, `hex-large` as a boss, enraged or stronger one (lib/footprint.py's `fit`: its rest pose
seen from above, with a margin for its widest clip), and a number scales it by that (1: as the
download is). It prints the scale and how far the rest pose and the widest clip reach across the
hex; check_footprint.py confirms the fit once the clips are built.

    ... --python packages/game-models/import_source.py -- <rigged.glb> <source.glb> [size=1024] [scale=hex]
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import footprint, rigged  # noqa: E402

# The hex's limits (rest, clips) each `scale` word fits the model to.
HEX = {"hex": footprint.REGULAR, "hex-large": footprint.LARGE}


def to_hex(limits, rig):
    """The scale that fits the skin, placed on its feet, to its hex within `limits`, printed with
    how far it reaches across the hex before and after."""

    def fitted(skin):
        pose = rig.data.pose_position
        rig.data.pose_position = "REST"
        try:
            # Evaluated and in world space, as check_footprint.py measures it: shape keys at
            # their weights count.
            rest = footprint.reach([skin])
        finally:
            rig.data.pose_position = pose
        fit = footprint.fit(rest, limits)
        print("HEX rest pose reaches %.3f of the hex as downloaded; scaled by %.4f: rest %.3f (limit %.2f), "
              "widest clip about %.3f (limit %.2f)" % (rest, fit, rest * fit, limits[0],
                                                     rest * fit * footprint.CLIP_MARGIN, limits[1]))
        return fit

    return fitted


args = sys.argv[sys.argv.index("--") + 1:]
download, source = args[0], args[1]
size = int(args[2]) if len(args) > 2 else 1024
scale = args[3] if len(args) > 3 else "hex"
if scale not in HEX:
    try:
        scale = float(scale)
    except ValueError:
        sys.exit("scale must be %s or a positive number, not %s" % (" or ".join(HEX), scale))
    if not math.isfinite(scale) or scale <= 0.0:
        sys.exit("scale must be a positive number, not %g" % scale)
# The colour's JPEG quality: the cel look's flat bands hide its artefacts well below lossless.
QUALITY = 90

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=download)
# The importer puts the shapes it draws bones with in a collection of its own, never exported.
shown = [obj for obj in bpy.context.scene.objects
         if not any("glTF_not_exported" in collection.name for collection in obj.users_collection)]
meshes = [obj for obj in shown if obj.type == "MESH"]
if len(meshes) != 1:
    sys.exit("expected one mesh in %s, found %d" % (download, len(meshes)))
mesh = meshes[0]
modifier = next((modifier for modifier in mesh.modifiers if modifier.type == "ARMATURE"), None)
rig = modifier.object if modifier is not None else None
for obj in list(bpy.context.scene.objects):
    if obj not in (mesh, rig):
        print("SOURCE dropped", obj.name)
        bpy.data.objects.remove(obj, do_unlink=True)

for material in mesh.data.materials:
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    colour = shader.inputs["Base Color"].links[0].from_node if shader.inputs["Base Color"].links else None
    # Only the base colour stays: no normal map, no metal or roughness map, no alpha. The links
    # go first: a node removed under a link Python still holds crashes Blender.
    for name in ("Alpha", "Metallic", "Roughness", "Normal"):
        for link in list(shader.inputs[name].links):
            links.remove(link)
    dropped = [node.name for node in nodes
               if node.type in {"TEX_IMAGE", "NORMAL_MAP", "SEPARATE_COLOR", "SEPARATE_RGB"} and node != colour]
    for name in dropped:
        nodes.remove(nodes[name])
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 1.0
    shader.inputs["Alpha"].default_value = 1.0
    material.use_backface_culling = True
    if colour is not None:
        image = colour.image
        # Its longer side shrinks to `size`, the other in proportion.
        shrink = size / max(image.size)
        if shrink < 1.0:
            image.scale(max(1, round(image.size[0] * shrink)), max(1, round(image.size[1] * shrink)))
        image.pack()
    print("SOURCE material", material.name, "colour", None if colour is None else tuple(colour.image.size))

# The game's toon look shades by the normals the mesh carries: smooth ones, from its own faces.
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
if mesh.data.has_custom_normals:
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
bpy.ops.object.shade_smooth()
if rig is not None:
    rigged.adopt(rig, mesh, to_hex(HEX[scale], rig) if scale in HEX else scale)
elif len(args) > 3:
    print("SOURCE unrigged: scale not applied; the model script places and sizes it")
bpy.ops.export_scene.gltf(
    filepath=source,
    export_format="GLB",
    export_animations=False,
    export_skins=rig is not None,
    export_yup=True,
    export_image_format="JPEG",
    export_jpeg_quality=QUALITY,
)
print("SOURCE", source, "triangles", sum(len(p.vertices) - 2 for p in mesh.data.polygons))
