class_name LootFound
extends RefCounted
## Event: a player stepped onto loot on the ground this tick (#203) and found it. It's gone from the
## region; `loot` holds what each player in this instance got from it, by slot, as {item id:
## amount}, rolled like a chest's (ChestOpened), but it isn't a chest, so quests don't count it.

var tile: Vector2i
## The player's entity who found it.
var finder_id: int
var loot: Dictionary[int, Dictionary]


func _init(on_tile: Vector2i, by_id: int, rolled: Dictionary[int, Dictionary]) -> void:
	tile = on_tile
	finder_id = by_id
	loot = rolled
