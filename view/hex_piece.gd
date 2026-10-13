## Something standing on one hex tile: centered on it, resting on the tile's top surface.
## A tool script, so its placement also shows in the editor.
@tool
class_name HexPiece
extends Node3D

@export var tile: Vector2i = Vector2i.ZERO:
	set(value):
		tile = value
		_place()
## Distance from this node's origin down to its bottom, e.g. half a cube's height.
@export var base_offset: float = 0.5:
	set(value):
		base_offset = value
		_place()


func _ready() -> void:
	_place()


## Where the piece stands when it is on its tile, relative to its parent.
func tile_position() -> Vector3:
	return position_on(tile)


## Where the piece stands on any tile, relative to its parent.
func position_on(on_tile: Vector2i) -> Vector3:
	return HexLayout.to_world(on_tile) + Vector3(0.0, HexGrid.TILE_HEIGHT + base_offset, 0.0)


func _place() -> void:
	position = tile_position()
