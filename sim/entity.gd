class_name Entity
extends RefCounted
## Something in the world with a stable id: the players, wild monsters and later totems.
## The core keeps only what every entity has (its id, its owner and its tile); features keep their
## own data per entity id, like components (e.g. MovementFeature's walks).

## The owner of an entity no player controls.
const NO_SLOT: int = -1

## Unique for the whole run and never reused, so replays and hashes can name entities.
var id: int = 0
## The player slot (0 to GameState.MAX_PLAYERS - 1) that controls the entity, or NO_SLOT.
var slot: int = NO_SLOT
var tile: Vector2i = Vector2i.ZERO


func _init(entity_id: int, owner_slot: int, start: Vector2i) -> void:
	id = entity_id
	slot = owner_slot
	tile = start
