class_name InkOutline
extends MeshInstance3D
## The comic look's ink outline (#14, #166), drawn once over the whole screen: ink wherever the
## depth jumps (ink_outline.gdshader). Every mesh gets it, open or closed, thin or not (a cape,
## hair, leaves), at the same width on screen, with no per-model work. It's a quad the shader
## stretches over the screen, so it's never culled and casts no shadow, and it draws after every
## other transparent thing, so the ink lies on top, except text in the world (TEXT_PRIORITY).

const SHADER: Shader = preload("res://slices/board/look/ink_outline.gdshader")
## The ink's draw order among transparent things: last but for the fog's cloud (FogCloud), which
## covers it, and text in the world, which would be crossed by the lines of what stands behind it
## otherwise.
const PRIORITY: int = Material.RENDER_PRIORITY_MAX - 2
## Text in the world (its outline one below), drawn above the ink.
const TEXT_PRIORITY: int = Material.RENDER_PRIORITY_MAX


func _ready() -> void:
	mesh = QuadMesh.new()
	extra_cull_margin = 16_384.0
	ignore_occlusion_culling = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink: ShaderMaterial = ShaderMaterial.new()
	ink.shader = SHADER
	ink.render_priority = PRIORITY
	ink.set_shader_parameter("ink", Toon.INK)
	material_override = ink


## Smooths the lines (four times the work) or draws them hard; Graphics decides with the
## anti-aliasing.
func set_smoothed(smoothed: bool) -> void:
	(material_override as ShaderMaterial).set_shader_parameter("smoothed", smoothed)


## Whether the lines are smoothed.
func is_smoothed() -> bool:
	var smoothed: bool = (material_override as ShaderMaterial).get_shader_parameter("smoothed")
	return smoothed
