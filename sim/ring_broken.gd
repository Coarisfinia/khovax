class_name RingBroken
extends RefCounted
## Event: a player's sealing ring broke this tick (#219): a wall segment gave way under the wild
## monsters pushing against it, nothing inside was caught, and the player's trail starts over.
## Enraging the monsters inside builds on this later (#220).

## The ring's player's entity, and their slot.
var catcher_id: int
var catcher_slot: int
## The segment that gave way, and every wall segment the ring had.
var tile: Vector2i
var walls: Array[Vector2i]
## The wild monsters that were inside, in id order.
var monster_ids: Array[int]


func _init(
	by_id: int,
	by_slot: int,
	failed_tile: Vector2i,
	wall_tiles: Array[Vector2i],
	inside: Array[int],
) -> void:
	catcher_id = by_id
	catcher_slot = by_slot
	tile = failed_tile
	walls = wall_tiles
	monster_ids = inside
