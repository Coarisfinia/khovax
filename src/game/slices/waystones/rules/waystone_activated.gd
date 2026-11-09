class_name WaystoneActivated
extends RefCounted
## Event: a player activated a waystone this tick (#1890), which is now their respawn point.

## The player's entity and slot.
var entity_id: int
var slot: int
## The waystone's tile.
var tile: Vector2i


func _init(activating_id: int, player_slot: int, stone: Vector2i) -> void:
	entity_id = activating_id
	slot = player_slot
	tile = stone
