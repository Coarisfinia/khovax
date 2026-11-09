@tool
class_name WaterSurface
extends MultiMeshInstance3D
## The water over a grid's water tiles (#1933): one instance per tile, just above the tile's top,
## all drawn by the one water shader (water.gdshader). Each instance tells the shader which of its
## edges are shore. HexGrid says which tiles are water; this only draws them.

const SHADER: Shader = preload("res://slices/board/look/water.gdshader")
const NODE_NAME: String = "Water"
## Just above the tile's top, so the two never fight over the same depth.
const LIFT: float = HexGrid.TILE_HEIGHT / 2.0 + 0.004
## As thin as a mesh may be: only the top is water, never the tile's sides.
const THICKNESS: float = 0.001
## The largest value a shore mask's channel holds: the Compatibility renderer keeps it in 8 bits.
const MASK_RANGE: float = 255.0

## The material every grid's water shares.
static var _shared: ShaderMaterial

## Each water tile's MultiMesh instance.
var _index: Dictionary[Vector2i, int] = {}


func _init() -> void:
	name = NODE_NAME
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.top_radius = HexLayout.SIZE * HexGrid.TILE_SCALE
	mesh.bottom_radius = mesh.top_radius
	mesh.height = THICKNESS
	mesh.cap_bottom = false
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	material_override = shared_material()


## The one material of the tiles' water.
static func shared_material() -> ShaderMaterial:
	if _shared == null:
		_shared = ShaderMaterial.new()
		_shared.shader = SHADER
		var edge: float = HexLayout.SIZE * HexGrid.TILE_SCALE * sqrt(3.0) / 2.0
		_shared.set_shader_parameter("edge_distance", edge)
	return _shared


## Draws water on the tiles of `water`, each at its transform in `placed` and in its color in
## `colors`; a neighbour counts as shore only when it's a tile of the grid and not water.
func show_tiles(
	water: Array[Vector2i],
	placed: Dictionary[Vector2i, Transform3D],
	colors: Dictionary[Vector2i, Color],
) -> void:
	_index.clear()
	multimesh.instance_count = water.size()
	for i: int in water.size():
		_index[water[i]] = i
	for tile: Vector2i in _index:
		var i: int = _index[tile]
		var lifted: Vector3 = Vector3(0.0, LIFT, 0.0)
		multimesh.set_instance_transform(i, placed[tile].translated(lifted))
		var color: Color = colors.get(tile, Color.WHITE)
		multimesh.set_instance_color(i, color)
		var mask: Color = Color(_shore_mask(tile, placed) / MASK_RANGE, 0.0, 0.0, 0.0)
		multimesh.set_instance_custom_data(i, mask)


## Gives `tile` the color `color`, if it's water.
func recolor(tile: Vector2i, color: Color) -> void:
	if _index.has(tile):
		multimesh.set_instance_color(_index[tile], color)


## One bit per shore edge, the bit of an edge at bit * 60 degrees on the ground plane, as the shader
## reads it.
func _shore_mask(tile: Vector2i, placed: Dictionary[Vector2i, Transform3D]) -> int:
	var mask: int = 0
	for direction: Vector2i in Hex.DIRECTIONS:
		var neighbour: Vector2i = tile + direction
		if placed.has(neighbour) and not _index.has(neighbour):
			var towards: Vector3 = HexLayout.to_world(direction)
			var bit: int = posmod(roundi(atan2(towards.z, towards.x) / (PI / 3.0)), 6)
			mask |= 1 << bit
	return mask
