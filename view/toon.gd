class_name Toon
extends RefCounted
## The comic-style look (#14): hard light bands instead of smooth shading, and bold ink outlines.
## Built from Godot's own material modes, so it runs in the Compatibility renderer (web) too: toon
## diffuse and specular for the bands. Every view gives its materials the look through here, so
## later models get it by default.
##
## The ink outline isn't per material or per mesh: InkOutline draws it once over the whole screen,
## wherever the depth jumps (#166). Per-mesh shells (an inverted hull) assume closed meshes and tore
## or doubled on open ones, like a floating "helmet" at hard edges or a black second cape.

## The ink color, for InkOutline and anything drawn in ink.
const INK: Color = Color(0.08, 0.07, 0.09)

## The toon copy of each imported material, made once and shared by every model that uses it.
static var _copies: Dictionary[StandardMaterial3D, StandardMaterial3D] = {}


## Gives `material` the toon look: banded light.
static func apply(material: StandardMaterial3D) -> void:
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON


## Gives every mesh under `root` the toon look, on toon copies of the imported materials, so the
## imported resources stay untouched. Models sharing a material share its one copy.
static func apply_to_model(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var meshes: MeshInstance3D = node as MeshInstance3D
		for surface: int in meshes.mesh.get_surface_count():
			var material: Material = meshes.get_active_material(surface)
			var source: StandardMaterial3D = material as StandardMaterial3D
			if source != null:
				meshes.set_surface_override_material(surface, _toon_copy(source))


static func _toon_copy(source: StandardMaterial3D) -> StandardMaterial3D:
	if not _copies.has(source):
		var copy: StandardMaterial3D = source.duplicate() as StandardMaterial3D
		apply(copy)
		_copies[source] = copy
	return _copies[source]
