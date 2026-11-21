"""How light a static model's surface is, as the game's materials draw it (#2595): the mean diffuse
albedo of its faces, weighted by their area, as a linear luminance (0 black, 1 white).

A face's albedo is its material's base colour: the texture sampled at its corners' UVs (the
nearest texel, turned from sRGB to linear) times the colour factor, or the factor alone without a
texture. Godot's StandardMaterial3D lights only the share a metal leaves diffuse, so it is
multiplied by one minus the metallic factor. A base colour fed by anything else than a texture and
a factor counts as white: the check can't tell, and passes it."""

import numpy as np

# Linear luminance of a linear RGB colour (Rec. 709).
LUMA = np.array([0.2126, 0.7152, 0.0722])


def to_linear(srgb):
    return np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)


def _base_colour(material):
    """The material's colour factor (linear RGB), its texture image or None, and its metallic."""
    if material is None or not material.use_nodes:
        return np.ones(3), None, 0.0
    bsdf = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return np.ones(3), None, 0.0
    base = bsdf.inputs["Base Color"]
    metallic = bsdf.inputs["Metallic"].default_value
    if not base.is_linked:
        return np.array(base.default_value[:3]), None, metallic
    # The glTF importer feeds a texture straight in, or through a multiply by the factor.
    factor, node = np.ones(3), base.links[0].from_node
    while node.type != "TEX_IMAGE":
        linked = [socket for socket in node.inputs if socket.is_linked]
        if not linked:
            return np.ones(3), None, metallic
        for socket in node.inputs:
            if socket.type == "RGBA" and not socket.is_linked:
                factor = factor * np.array(socket.default_value[:3])
        node = linked[0].links[0].from_node
    return factor, node.image, metallic


def _texels(image, cache):
    if image.name not in cache:
        pixels = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(pixels)
        width, height = image.size
        cache[image.name] = to_linear(pixels.reshape(height, width, image.channels)[:, :, :3])
    return cache[image.name]


def mean(objects):
    """The area-weighted mean diffuse albedo of the meshes among `objects`, or None without faces."""
    total, area, cache = 0.0, 0.0, {}
    for obj in objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        uvs = mesh.uv_layers.active
        slots = [slot.material for slot in obj.material_slots]
        # Faces measured in the mesh's own units, scaled to the scene's.
        scale = abs(obj.matrix_world.to_3x3().determinant()) ** (2.0 / 3.0)
        for polygon in mesh.polygons:
            material = slots[polygon.material_index] if slots else None
            factor, image, metallic = _base_colour(material)
            colour = factor
            if image is not None and uvs is not None and image.size[0] > 0:
                texels = _texels(image, cache)
                height, width = texels.shape[:2]
                sampled = np.zeros(3)
                for loop in polygon.loop_indices:
                    u, v = uvs.data[loop].uv
                    sampled += texels[int(v % 1.0 * height) % height, int(u % 1.0 * width) % width]
                colour = factor * sampled / len(polygon.loop_indices)
            total += polygon.area * scale * float(colour @ LUMA) * (1.0 - metallic)
            area += polygon.area * scale
    return total / area if area > 0.0 else None
