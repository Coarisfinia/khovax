class_name SentToSpawn
extends RefCounted
## Event: a player is sent back to the world's spawn this tick (#457), when their HP ran out and
## nobody can bring them back. The world moves them onto their start in the starting instance,
## after every instance has stepped, as a new entity: at full HP.

## The player's entity, still in its instance when the event is raised.
var entity_id: int
var slot: int


func _init(sent_id: int, player_slot: int) -> void:
	entity_id = sent_id
	slot = player_slot
