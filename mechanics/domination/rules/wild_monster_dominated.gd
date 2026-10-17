class_name WildMonsterDominated
extends RefCounted
## Event: a player's trail closed a ring around a wild monster this tick, and dominated it. The
## monster's entity is already gone; views play the domination from this, and the dominator's
## profile takes the species (#132, #133).

var monster_id: int
## The dominating player's entity, and their slot: whoever reads the event later (EventBus, #184)
## still knows whose domination it was, even when the player has left the instance since.
var dominator_id: int
var dominator_slot: int
var tile: Vector2i
## The dominated monster's species id.
var species: String
## What each player in the instance did for the ring that dominated it, by slot (#86): how many
## tiles of its wall they colored, and how many ticks they stood on its wall while it sealed. A slot
## that did neither is missing.
var walls_colored: Dictionary[int, int] = {}
var braced_ticks: Dictionary[int, int] = {}


func _init(
	dominated_id: int,
	by_id: int,
	by_slot: int,
	on_tile: Vector2i,
	species_id: String = "",
) -> void:
	monster_id = dominated_id
	dominator_id = by_id
	dominator_slot = by_slot
	tile = on_tile
	species = species_id
