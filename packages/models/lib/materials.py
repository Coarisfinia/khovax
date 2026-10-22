"""Materials that survive the game's cel shading: flat colours, and an emissive glow that the
Compatibility renderer (web, Android) shows too. Keep a model to about four."""

import bpy


def material(name, color, glow=0.0, roughness=0.8, flat=False):
    """A flat colour; with `glow` above 0, it also emits its colour at that strength."""
    mat = bpy.data.materials.new(name)
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    if glow > 0.0:
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = glow
    return mat


def palette(colors):
    """Materials by name from {name: (rgba, glow)}."""
    return {name: material(name, color, glow) for name, (color, glow) in colors.items()}
