class_name ChestOpened
extends RefCounted
## Event: a player walked onto a treasure chest this tick and opened it. It's gone from the region;
## `loot` holds what each player in the session got from it, by slot, as {item id: amount}.

var tile: Vector2i
## The player's entity who opened it.
var opener_id: int
var loot: Dictionary[int, Dictionary]


func _init(on_tile: Vector2i, by_id: int, rolled: Dictionary[int, Dictionary]) -> void:
	tile = on_tile
	opener_id = by_id
	loot = rolled
