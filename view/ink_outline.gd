class_name InkOutline
extends MeshInstance3D
## The comic look's ink outline (#14, #166), drawn once over the whole screen: ink wherever the
## depth jumps (view/ink_outline.gdshader). Every mesh gets it, open or closed, thin or not (a cape,
## hair, leaves), at the same width on screen, with no per-model work. It's a quad the shader
## stretches over the screen, so it's never culled and casts no shadow, and it draws after every
## other transparent thing, so the ink lies on top.

const SHADER: Shader = preload("res://view/ink_outline.gdshader")


func _ready() -> void:
	mesh = QuadMesh.new()
	extra_cull_margin = 16_384.0
	ignore_occlusion_culling = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink: ShaderMaterial = ShaderMaterial.new()
	ink.shader = SHADER
	ink.render_priority = Material.RENDER_PRIORITY_MAX
	ink.set_shader_parameter("ink", Toon.INK)
	material_override = ink
