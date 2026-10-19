class_name DominatedMonster
extends RefCounted
## A monster the player dominated and owns (a `dominated_monster`, #45), kept in the profile between
## sessions. Its species is an id into the content data (#72), and its short id the one it had in
## the wild (#700), which tells it apart from every other monster of its species in the world.

## Unique in the profile and never reused.
var id: int = 0
var species: String = ""
var short_id: String = ""
var level: int = 1


func _init(
	monster_id: int = 0,
	species_id: String = "",
	start_level: int = 1,
	monster_short_id: String = "",
) -> void:
	id = monster_id
	species = species_id
	level = start_level
	short_id = monster_short_id


func to_data() -> Dictionary[String, Variant]:
	var data: Dictionary[String, Variant] = {
		"id": id,
		"species": species,
		"short_id": short_id,
		"level": level,
	}
	return data
