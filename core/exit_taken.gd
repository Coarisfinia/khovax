class_name ExitTaken
extends RefCounted
## Event: a player walked out of the instance through an exit this tick (#154). The world moves
## them into the instance the exit leads to, after every instance has stepped.

## The leaving player's entity, still in the instance when the event is raised.
var entity_id: int
var slot: int
## The instance blueprint the exit leads to.
var target: String


func _init(leaving_id: int, player_slot: int, leads_to: String) -> void:
	entity_id = leaving_id
	slot = player_slot
	target = leads_to
