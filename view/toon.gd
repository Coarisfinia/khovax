class_name Toon
extends RefCounted
## The comic-style look (#14): hard light bands instead of smooth shading, and bold ink outlines.
## Built from Godot's own material modes, so it runs in the Compatibility renderer (web) too:
## toon diffuse and specular for the bands, and an outline pass that draws the mesh's back faces,
## grown a little, unlit in the ink color (inverted hull, no extra meshes). Every view gives its
## materials the look through here, so later models get it by default.

const INK: Color = Color(0.08, 0.07, 0.09)
## How far the outline pass grows the mesh, in world units: its thickness.
const OUTLINE_WIDTH: float = 0.04

## The one outline pass every toon material shares.
static var _outline: StandardMaterial3D = null


## Gives `material` the toon look: banded light and the ink outline.
static func apply(material: StandardMaterial3D) -> void:
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.next_pass = outline()


## Gives every mesh under `root` the toon look, on its own copies of the imported materials, so
## the imported resources stay untouched.
static func apply_to_model(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var meshes: MeshInstance3D = node as MeshInstance3D
		for surface: int in meshes.mesh.get_surface_count():
			var material: Material = meshes.get_active_material(surface)
			var source: StandardMaterial3D = material as StandardMaterial3D
			if source != null:
				meshes.set_surface_override_material(surface, _toon_copy(source))


## The shared outline pass.
static func outline() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = INK
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = OUTLINE_WIDTH
	return _outline


static func _toon_copy(source: StandardMaterial3D) -> StandardMaterial3D:
	var copy: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	apply(copy)
	return copy
