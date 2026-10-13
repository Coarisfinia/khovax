class_name EntityMoved
extends RefCounted
## Event: an entity started moving from one tile to the next this tick. Features later in the
## order react to it (the trail grows with it).

var entity_id: int
var from: Vector2i
var to: Vector2i


func _init(moved_id: int, from_tile: Vector2i, to_tile: Vector2i) -> void:
	entity_id = moved_id
	from = from_tile
	to = to_tile
