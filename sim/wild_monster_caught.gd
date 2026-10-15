class_name WildMonsterCaught
extends RefCounted
## Event: a player's trail closed a ring around a wild monster this tick, and caught it. The
## monster's entity is already gone; views play the catch from this, and the catcher's profile
## takes the species (#132, #133).

var monster_id: int
## The catching player's entity.
var catcher_id: int
var tile: Vector2i
## The caught monster's species id.
var species: String


func _init(caught_id: int, by_id: int, on_tile: Vector2i, species_id: String = "") -> void:
	monster_id = caught_id
	catcher_id = by_id
	tile = on_tile
	species = species_id
