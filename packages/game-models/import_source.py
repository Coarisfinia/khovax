"""Turns a textured model from a generator's download into the source a model script builds from
(#1476): its mesh with its UVs and only its base colour texture, its longer side shrunk to
`size`, opaque, single-sided and matte. A generator's export carries far more than the game's
cel look shows (a normal map, a metal and roughness map, each as large as the colour), and the
game's other models are a small share of its size; the model script then places, rigs and
animates the source.

    uv run --locked packages/game-models/blender.py --background --factory-startup \
        --python packages/game-models/import_source.py -- <download.glb> <source.glb> [size=1024]

The source keeps the download's axes and origin: the model script places it on its feet.
"""

import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
download, source = args[0], args[1]
size = int(args[2]) if len(args) > 2 else 1024
# The colour's JPEG quality: the cel look's flat bands hide its artefacts well below lossless.
QUALITY = 90

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=download)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(meshes) != 1:
    sys.exit("expected one mesh in %s, found %d" % (download, len(meshes)))
mesh = meshes[0]
for obj in list(bpy.context.scene.objects):
    if obj is not mesh:
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
bpy.ops.export_scene.gltf(
    filepath=source,
    export_format="GLB",
    export_animations=False,
    export_skins=False,
    export_yup=True,
    export_image_format="JPEG",
    export_jpeg_quality=QUALITY,
)
print("SOURCE", source, "triangles", sum(len(p.vertices) - 2 for p in mesh.data.polygons))
