class_name InstanceEntered
extends RefCounted
## Event: a player came into another instance this tick (#370), by starting in it when the world
## starts or by arriving through an exit. The World raises it, not a feature, since only the world
## sees a player change instances. Quests count it for that player (an entered step).

## The instance's blueprint name.
var instance: String
## The player's entity (in that instance) and slot.
var entity_id: int
var slot: int


func _init(instance_name: String, entering_id: int, player_slot: int) -> void:
	instance = instance_name
	entity_id = entering_id
	slot = player_slot
