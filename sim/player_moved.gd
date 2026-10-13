class_name PlayerMoved
extends RefCounted
## Event: the player started moving from one tile to the next this tick. Features later in the
## order react to it (the trail grows with it).

var from: Vector2i
var to: Vector2i


func _init(from_tile: Vector2i, to_tile: Vector2i) -> void:
	from = from_tile
	to = to_tile
