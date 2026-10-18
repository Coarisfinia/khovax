class_name EntityFell
extends RefCounted
## Event: a player or a companion reached 0 HP this tick (#455). What happens then is its own rule:
## a companion returns to its player (#456), a player is knocked down or goes back to the spawn
## (#457).

var entity_id: int


func _init(fallen_id: int) -> void:
	entity_id = fallen_id
