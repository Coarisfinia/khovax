class_name WildMonsterCaught
extends RefCounted
## Event: a player's trail closed a ring around a wild monster this tick, and caught it. The
## monster's entity is already gone; views play the catch from this, and the catcher's profile
## takes the species (#132, #133).

var monster_id: int
## The catching player's entity, and their slot: whoever reads the event later (EventBus, #184)
## still knows whose catch it was, even when the player has left the instance since.
var catcher_id: int
var catcher_slot: int
var tile: Vector2i
## The caught monster's species id.
var species: String
## What each player in the instance did for the ring that caught it, by slot (#86): how many tiles
## of its wall they colored, and how many ticks they stood on its wall while it sealed. A slot that
## did neither is missing.
var walls_colored: Dictionary[int, int] = {}
var braced_ticks: Dictionary[int, int] = {}


func _init(
	caught_id: int,
	by_id: int,
	by_slot: int,
	on_tile: Vector2i,
	species_id: String = "",
) -> void:
	monster_id = caught_id
	catcher_id = by_id
	catcher_slot = by_slot
	tile = on_tile
	species = species_id
