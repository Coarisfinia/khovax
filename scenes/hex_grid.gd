## A flat hex grid of `radius` rings around the origin, one hexagonal tile per cell.
## A tool script, so the grid also shows in the editor.
##
## The tiles are generated from `radius` and live under a child container that has no owner: they
## are never saved into the scene, only rebuilt. Only that container's children are ever removed,
## so nodes added to the grid by hand are left alone.
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

var _material := StandardMaterial3D.new()
var _tiles := Node3D.new()


func _ready() -> void:
	_material.albedo_color = tile_color
	_tiles.name = TILES_NODE
	add_child(_tiles)
	_build()


func tile_node(tile: Vector2i) -> MeshInstance3D:
	return _tiles.get_node_or_null(_tile_name(tile)) as MeshInstance3D


func tile_count() -> int:
	return _tiles.get_child_count()


func _build() -> void:
	# Freed right away rather than queued: the tiles have no owner, so the editor holds no
	# references to them, and the rebuilt tiles reuse the same names.
	for child: Node in _tiles.get_children():
		_tiles.remove_child(child)
		child.free()

	# A cylinder with six segments is a hexagonal prism, already pointy-top like Hex.
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.top_radius = Hex.SIZE * TILE_SCALE
	mesh.bottom_radius = Hex.SIZE * TILE_SCALE
	mesh.height = TILE_HEIGHT
	mesh.material = _material

	for tile: Vector2i in Hex.disc(radius):
		var node := MeshInstance3D.new()
		node.name = _tile_name(tile)
		node.mesh = mesh
		node.position = Hex.to_world(tile) + Vector3(0.0, TILE_HEIGHT / 2.0, 0.0)
		_tiles.add_child(node)


static func _tile_name(tile: Vector2i) -> String:
	return "Tile_%d_%d" % [tile.x, tile.y]
