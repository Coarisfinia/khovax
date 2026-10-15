class_name Toon
extends RefCounted
## The comic-style look (#14): hard light bands instead of smooth shading, and bold ink outlines.
## Built from Godot's own material modes, so it runs in the Compatibility renderer (web) too:
## toon diffuse and specular for the bands, and an outline pass that draws the mesh's back faces,
## grown a little, unlit in the ink color (inverted hull). Every view gives its materials the look
## through here, so later models get it by default.
##
## A model's outline is a hull of its own (#162): a copy of each mesh whose normals are averaged
## wherever vertices share a position. Grown along the imported normals, the shell tore apart at a
## mesh's hard edges (a floating black "helmet" around the head); grown along the averaged ones,
## every corner moves the same way and the shell stays closed. The copy is made once per mesh.

const INK: Color = Color(0.08, 0.07, 0.09)
## How far the outline pass grows the mesh, in world units: its thickness.
const OUTLINE_WIDTH: float = 0.04
## The name of a model part's outline hull, a child of the part.
const HULL: String = "OutlineHull"

## The one outline pass every toon material shares.
static var _outline: StandardMaterial3D = null
## The toon copy of each imported material, made once and shared by every model that uses it.
static var _copies: Dictionary[StandardMaterial3D, StandardMaterial3D] = {}
## The outline copy of each imported mesh and set of opaque surfaces, with averaged normals, made
## once and shared, by "<mesh id>:<surfaces>".
static var _hulls: Dictionary[String, ArrayMesh] = {}


## Gives `material` the toon look: banded light and, with `outlined`, the ink outline as its next
## pass (simple closed shapes like the tiles; models get a hull of their own instead). A
## transparent material gets no outline: an opaque ink silhouette would show through it.
static func apply(material: StandardMaterial3D, outlined: bool = true) -> void:
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if outlined and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		material.next_pass = outline()


## Gives every mesh under `root` the toon look, on toon copies of the imported materials, so the
## imported resources stay untouched, and an outline hull as its child. Models sharing a material
## or a mesh share its one copy.
static func apply_to_model(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var meshes: MeshInstance3D = node as MeshInstance3D
		# A model given the look before keeps its one hull per part.
		if meshes.name == HULL or meshes.get_node_or_null(HULL) != null:
			continue
		var opaque: Array[int] = []
		for surface: int in meshes.mesh.get_surface_count():
			var material: Material = meshes.get_active_material(surface)
			var source: StandardMaterial3D = material as StandardMaterial3D
			if source != null:
				meshes.set_surface_override_material(surface, _toon_copy(source))
			if source == null or source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				opaque.append(surface)
		if not opaque.is_empty():
			meshes.add_child(_hull_for(meshes, opaque))


## The outline hull for `meshes`: its mesh's opaque surfaces with averaged normals, in ink, on the
## same skeleton and skin, so it animates with the part and hides with it.
static func _hull_for(meshes: MeshInstance3D, opaque: Array[int]) -> MeshInstance3D:
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.name = HULL
	hull.mesh = _hull_mesh(meshes.mesh as ArrayMesh, opaque)
	hull.material_override = outline()
	# The ink shell only draws the outline: it casts no shadow of its own.
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.skin = meshes.skin
	# The part's skeleton path is relative to the part; the hull sits one level below it.
	if not meshes.skeleton.is_empty():
		hull.skeleton = NodePath("../" + str(meshes.skeleton))
	return hull


## A copy of `mesh`'s `opaque` surfaces whose every normal is the average over all vertices at its
## position, made once per mesh and surfaces. Blend shapes aren't copied: the models in use have
## none, and one that does needs them averaged too.
static func _hull_mesh(mesh: ArrayMesh, opaque: Array[int]) -> ArrayMesh:
	var key: String = "%d:%s" % [mesh.get_instance_id(), opaque]
	if _hulls.has(key):
		return _hulls[key]
	var hull: ArrayMesh = ArrayMesh.new()
	for surface: int in opaque:
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		arrays[Mesh.ARRAY_NORMAL] = _averaged(vertices, normals)
		arrays[Mesh.ARRAY_TANGENT] = null
		var bones: int = mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		hull.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, bones)
	_hulls[key] = hull
	return hull


## `normals`, each replaced by the normalized sum of the normals of every vertex at its position.
static func _averaged(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
) -> PackedVector3Array:
	var sums: Dictionary[Vector3, Vector3] = {}
	for i: int in vertices.size():
		sums[vertices[i]] = sums.get(vertices[i], Vector3.ZERO) + normals[i]
	var averaged: PackedVector3Array = PackedVector3Array()
	var _sized: int = averaged.resize(vertices.size())
	for i: int in vertices.size():
		averaged[i] = sums[vertices[i]].normalized()
	return averaged


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
	if not _copies.has(source):
		var copy: StandardMaterial3D = source.duplicate() as StandardMaterial3D
		apply(copy, false)
		_copies[source] = copy
	return _copies[source]
