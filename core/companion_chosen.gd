class_name CompanionChosen
extends RefCounted
## Event: a player chose another of their carried monsters as their companion this tick (#55). The
## world makes it their companion in every instance, after every instance has stepped; the companion
## feature then sends the old one off and lets the new one join them.

var slot: int
## Its place in the player's carried order, from 0 (GameState.carried).
var place: int


func _init(player_slot: int, carried_place: int) -> void:
	slot = player_slot
	place = carried_place
