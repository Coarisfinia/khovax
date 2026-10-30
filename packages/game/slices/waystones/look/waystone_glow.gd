class_name WaystoneGlow
extends Node3D
## The glow of the waystones this machine's player activated (#1890): the standing stone's hole
## (its model's `glow` part, the hole's inner wall) shines, and a soft light in it lights the stone
## around it. A waystone not yet activated shows that part as plain stone. It changes how bright the
## stone is, not only its colour (#68), and a notice says so when one is activated
## (WaystoneNoticeTie). It lights the stones TileDecorations stands, and only reads the state.

## The name of the model's part that glows, its material's name in the model.
const GLOW_PART: String = "glow"
## The glow's colour, and the light's reach in world units and its strength.
const COLOR: Color = Color(0.55, 0.9, 1.0)
const LIGHT_RANGE: float = 1.2
const LIGHT_ENERGY: float = 1.5
## The meta a stone's figure keeps whether it's lit under.
const LIT: StringName = &"waystone_lit"

@export var driver: Session
## Whose waystones light up: this machine's player's.
@export var input: LocalInput
## The decorations the waystones stand among.
@export var decorations: TileDecorations

## The lit hole's material, shared by every lit stone.
var _glowing: StandardMaterial3D


func _ready() -> void:
	_glowing = StandardMaterial3D.new()
	_glowing.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glowing.albedo_color = COLOR


func _process(_delta: float) -> void:
	show_state()


## Lights the waystones this machine's player activated and leaves the others unlit. Called every
## frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null or driver.world == null or decorations == null:
		return
	var slot: int = input.slot if input != null else 0
	var here: String = driver.world.instance_of(slot)
	var lit: Array[Vector2i] = WaystoneFeature.activated_in(driver.state, slot, here)
	var region: Region = driver.state.region
	for tile: Vector2i in decorations.figures:
		if region.terrain.get(tile, "") == WaystoneFeature.KIND:
			light(decorations.figures[tile], lit.has(tile))


## Whether the waystone `figure` shows lit.
static func is_lit(figure: Node3D) -> bool:
	return figure.get_meta(LIT, false)


## Lights the waystone `figure`, or puts its light out, unless it already shows so.
func light(figure: Node3D, on: bool) -> void:
	if is_lit(figure) == on:
		return
	figure.set_meta(LIT, on)
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var meshes: MeshInstance3D = node as MeshInstance3D
		for surface: int in meshes.mesh.get_surface_count():
			var source: Material = meshes.mesh.surface_get_material(surface)
			if source == null or source.resource_name != GLOW_PART:
				continue
			_light_surface(meshes, surface, on)


## Swaps the hole's surface `surface` of `meshes` to the glowing material, with a light in the
## hole's middle, or back to the stone it showed before (its toon copy, Toon) and no light.
func _light_surface(meshes: MeshInstance3D, surface: int, on: bool) -> void:
	var light_name: String = "WaystoneLight%d" % surface
	var stone_meta: StringName = StringName("waystone_stone_%d" % surface)
	var shining: Node = meshes.get_node_or_null(light_name)
	if not on:
		var stone: Material = meshes.get_meta(stone_meta, null)
		meshes.set_surface_override_material(surface, stone)
		if shining != null:
			shining.queue_free()
		return
	meshes.set_meta(stone_meta, meshes.get_surface_override_material(surface))
	meshes.set_surface_override_material(surface, _glowing)
	if shining == null:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = light_name
		lamp.light_color = COLOR
		lamp.omni_range = LIGHT_RANGE
		lamp.light_energy = LIGHT_ENERGY
		lamp.position = _middle(meshes.mesh, surface)
		meshes.add_child(lamp)


## The middle of `surface` of `mesh`, in the mesh's own space: the hole's.
static func _middle(mesh: Mesh, surface: int) -> Vector3:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if points.is_empty():
		return Vector3.ZERO
	var bounds: AABB = AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		bounds = bounds.expand(point)
	return bounds.get_center()
