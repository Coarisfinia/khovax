class_name PieceEntered
extends RefCounted
## Event: a player came to stand in another region piece this tick (#350), by stepping onto it,
## starting on it or arriving on it through an exit. Quests count it for that player (an entered
## step).

## The piece's id: its file name in its instance blueprint's folder.
var piece: String
## The player's entity and slot.
var entity_id: int
var slot: int


func _init(piece_id: String, entering_id: int, player_slot: int) -> void:
	piece = piece_id
	entity_id = entering_id
	slot = player_slot
