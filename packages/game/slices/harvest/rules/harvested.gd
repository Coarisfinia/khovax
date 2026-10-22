class_name Harvested
extends RefCounted
## Event: a wild monster felled this tick (#629) dropped crafting materials where it lies. `loot`
## holds what each player in the instance got from it, by slot, as {item id: amount}.

var monster_id: int
var species: String
var tile: Vector2i
var loot: Dictionary[int, Dictionary]


func _init(
	felled_id: int,
	species_id: String,
	on_tile: Vector2i,
	rolled: Dictionary[int, Dictionary],
) -> void:
	monster_id = felled_id
	species = species_id
	tile = on_tile
	loot = rolled
