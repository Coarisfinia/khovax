class_name DominationLoot
extends RefCounted
## Event: the loot for a wild monster dominated this tick (#86). `loot` holds what each player who
## did enough for its ring got, by slot, as {item id: amount}; a slot that's missing earned nothing.

var monster_id: int
var species: String
var loot: Dictionary[int, Dictionary]


func _init(dominated_id: int, species_id: String, rolled: Dictionary[int, Dictionary]) -> void:
	monster_id = dominated_id
	species = species_id
	loot = rolled
