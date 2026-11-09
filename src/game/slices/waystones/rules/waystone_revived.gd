class_name WaystoneRevived
extends RefCounted
## Event: a player next to a waystone got their fainted beasts back this tick (#1891), while the
## host has them revived on waystones.

## The player's slot.
var slot: int
## The short ids of the beasts brought back, in their carried order.
var short_ids: PackedStringArray


func _init(player_slot: int, revived: PackedStringArray) -> void:
	slot = player_slot
	short_ids = revived
