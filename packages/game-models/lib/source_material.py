"""A generator's material made into a source's (#1476): only its base colour texture, shrunk, with
no glow, opaque, single-sided and matte. A generator's export carries far more than the game's
cel look shows (a normal map, a metal and roughness map, each as large as the colour)."""


def strip(material, size):
    """Strips `material` to its base colour, its texture's longer side shrunk to `size` and packed;
    returns the colour's image node, or None when it has none."""
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    colour = shader.inputs["Base Color"].links[0].from_node if shader.inputs["Base Color"].links else None
    # Only the base colour stays: no normal map, no metal or roughness map, no alpha. The links
    # go first: a node removed under a link Python still holds crashes Blender.
    for name in ("Alpha", "Metallic", "Roughness", "Normal", "Emission Color"):
        for link in list(shader.inputs[name].links):
            links.remove(link)
    dropped = [node.name for node in nodes
               if node.type in {"TEX_IMAGE", "NORMAL_MAP", "SEPARATE_COLOR", "SEPARATE_RGB"} and node != colour]
    for name in dropped:
        nodes.remove(nodes[name])
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 1.0
    shader.inputs["Alpha"].default_value = 1.0
    # A download with an emissive map (#1609) keeps its emissive factor once the map goes, white,
    # and would glow all over: no glow.
    shader.inputs["Emission Strength"].default_value = 0.0
    material.use_backface_culling = True
    if colour is not None:
        image = colour.image
        # Its longer side shrinks to `size`, the other in proportion.
        shrink = size / max(image.size)
        if shrink < 1.0:
            image.scale(max(1, round(image.size[0] * shrink)), max(1, round(image.size[1] * shrink)))
        image.pack()
    return colour
