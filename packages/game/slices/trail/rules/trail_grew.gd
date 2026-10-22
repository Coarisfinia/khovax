class_name TrailGrew
extends RefCounted
## Event: an entity's trail got a new tile this tick (walking over its own trail again raises
## none). Features later in the order react to it: only a trail that grew can close a new ring.

var entity_id: int
## The tile the entity came from, and the new tile on its trail.
var from: Vector2i
var to: Vector2i


func _init(grown_id: int, from_tile: Vector2i, to_tile: Vector2i) -> void:
	entity_id = grown_id
	from = from_tile
	to = to_tile
