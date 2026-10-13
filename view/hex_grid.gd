## A flat hex grid of `radius` rings around the origin, one hexagonal tile per cell.
## A tool script, so the grid also shows in the editor.
##
## All tiles are instances of one MultiMesh: one draw call, and nothing per tile in the scene tree.
## The tiles are rebuilt from `radius` and never saved; nodes added to the grid by hand are kept.
@tool
class_name HexGrid
extends Node3D

## Height of a tile; its top surface is at this y.
const TILE_HEIGHT: float = 0.1
## Tiles are drawn slightly smaller than their cell, so the gaps read as grid lines.
const TILE_SCALE: float = 0.94
const TILES_NODE: String = "Tiles"

@export_range(0, 12) var radius: int = 3:
	set(value):
		radius = value
		if is_node_ready():
			_build()
@export var tile_color: Color = Color(0.36, 0.55, 0.32):
	set(value):
		tile_color = value
		_material.albedo_color = value

var _material: StandardMaterial3D = StandardMaterial3D.new()
var _mesh: CylinderMesh = CylinderMesh.new()
var _tiles: MultiMeshInstance3D = MultiMeshInstance3D.new()
## Each tile's transform, as given to the MultiMesh. Kept here because a MultiMesh can't be read
## back under the headless dummy renderer.
var _transforms: Dictionary[Vector2i, Transform3D] = {}


func _ready() -> void:
	_material.albedo_color = tile_color
	# A cylinder with six segments is a hexagonal prism, already pointy-top like Hex.
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_mesh.top_radius = HexLayout.SIZE * TILE_SCALE
	_mesh.bottom_radius = HexLayout.SIZE * TILE_SCALE
	_mesh.height = TILE_HEIGHT
	_mesh.material = _material
	_tiles.name = TILES_NODE
	_tiles.multimesh = MultiMesh.new()
	_tiles.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_tiles.multimesh.mesh = _mesh
	add_child(_tiles)
	_build()


func has_tile(tile: Vector2i) -> bool:
	return _transforms.has(tile)


func tile_count() -> int:
	return _tiles.multimesh.instance_count


## The tile's transform relative to the grid; the identity basis when the tile isn't on the grid.
func tile_transform(tile: Vector2i) -> Transform3D:
	return _transforms.get(tile, Transform3D.IDENTITY)


func tile_mesh() -> CylinderMesh:
	return _mesh


func _build() -> void:
	var tiles: Array[Vector2i] = Hex.disc(radius)
	_transforms.clear()
	_tiles.multimesh.instance_count = tiles.size()
	for i: int in tiles.size():
		var tile: Vector2i = tiles[i]
		var center: Vector3 = HexLayout.to_world(tile) + Vector3(0.0, TILE_HEIGHT / 2.0, 0.0)
		_transforms[tile] = Transform3D(Basis.IDENTITY, center)
		_tiles.multimesh.set_instance_transform(i, _transforms[tile])
