class_name PlaceReached
extends RefCounted
## Event: a player stepped into a place this tick (#339), onto a tile of it from one outside it.
## Quests count it for that player (a reached step).

## The place's id, as the region piece's legend names it.
var place: String
## The player's entity and slot.
var entity_id: int
var slot: int


func _init(place_id: String, reaching_id: int, player_slot: int) -> void:
	place = place_id
	entity_id = reaching_id
	slot = player_slot
